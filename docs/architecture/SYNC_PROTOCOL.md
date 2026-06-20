# Sendero — Sync Protocol

**Version:** 0.1
**Date:** 2026-06-20

---

## 1. Design Goals

1. **No data loss.** A track recorded fully offline must reach the cloud eventually.
2. **No blocking.** The UI never waits for network. All reads/writes hit local DB.
3. **Predictable conflicts.** Conflict resolution rules are simple enough that users can understand them.
4. **Observable state.** Every item knows whether it is synced, pending, or failed.
5. **Resumable.** A sync interrupted mid-way resumes from where it left off, no duplicates.

---

## 2. Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│                        App Layer                         │
│  ┌────────────┐   write    ┌──────────────────────────┐  │
│  │   UI /     │──────────►│      Local DB (Drift)    │  │
│  │  BLoC/     │           │  routes, tracks, photos, │  │
│  │  Riverpod  │◄──────────│  sync_queue, ...         │  │
│  └────────────┘   stream  └──────────┬───────────────┘  │
│                                      │                   │
└──────────────────────────────────────┼───────────────────┘
                                       │ async, when online
                              ┌────────▼────────┐
                              │  SyncService    │
                              │  (background    │
                              │   isolate)      │
                              └────────┬────────┘
                                       │ HTTPS / Supabase SDK
                              ┌────────▼────────┐
                              │  Supabase       │
                              │  (Postgres +    │
                              │   Storage +     │
                              │   Realtime)     │
                              └─────────────────┘
```

---

## 3. Sync Queue

Every local write (create, update, soft-delete) appends an entry to `sync_queue` within the same SQLite transaction. This is atomic: either the local write and the queue entry both succeed, or neither does.

```dart
// Example: saving a route
await db.transaction(() async {
  await db.into(db.routes).insertOnConflictUpdate(route);
  await db.into(db.syncQueue).insert(SyncQueueEntry(
    entityType: 'route',
    entityId:   route.id,
    operation:  'upsert',
    payload:    jsonEncode(route.toJson()),
    priority:   5,
    createdAt:  DateTime.now().millisecondsSinceEpoch,
    nextRetryAt: DateTime.now().millisecondsSinceEpoch,
  ));
});
```

### Queue entry lifecycle

```
CREATED
   │
   ▼
PENDING (nextRetryAt <= now)
   │
   ├─[network unavailable]─► wait, retry later
   │
   ├─[attempt succeeds]────► DELETED from queue
   │
   └─[attempt fails]──────► attempt_count++
                             nextRetryAt = now + backoff(attempt_count)
                             [if attempt_count > 20] → DEAD (kept, alerts user)
```

### Backoff schedule

| Attempt | Delay |
|---|---|
| 1 | 30s |
| 2 | 2m |
| 3 | 10m |
| 4 | 30m |
| 5 | 2h |
| 6–10 | 6h |
| 11–20 | 24h |
| > 20 | Dead — manual retry required |

---

## 4. SyncService

Runs in a Flutter background isolate (separate from UI thread). Triggered by:

1. **App foreground event** — checks queue immediately on open
2. **Connectivity restored** — `connectivity_plus` fires event, service wakes
3. **Periodic timer** — every 15 minutes while app is backgrounded (via `background_fetch`)
4. **Manual trigger** — pull-to-refresh on profile/history screen

```dart
class SyncService {
  final LocalDatabase db;
  final SupabaseClient supabase;

  Future<void> flush() async {
    if (!await _isOnline()) return;

    final pending = await db.syncQueue.getPendingOrderedByPriority();

    for (final entry in pending) {
      try {
        await _dispatch(entry);
        await db.syncQueue.delete(entry.id);
      } on SyncConflictException catch (e) {
        await _resolveConflict(entry, e.remoteVersion);
      } on NetworkException {
        break; // stop processing, will retry on next trigger
      } on SyncException catch (e) {
        await db.syncQueue.recordFailure(entry.id, e.message);
      }
    }

    // Pull remote changes for entities we care about
    await _pullRemoteChanges();
  }

  Future<void> _dispatch(SyncQueueEntry entry) async {
    switch (entry.entityType) {
      case 'route':    return _syncRoute(entry);
      case 'track':    return _syncTrack(entry);
      case 'photo':    return _syncPhoto(entry);
      case 'review':   return _syncReview(entry);
      default: throw SyncException('Unknown entity: ${entry.entityType}');
    }
  }
}
```

---

## 5. Conflict Resolution

### Strategy: Last-Write-Wins (LWW) per entity

Sendero is primarily a single-user, single-device app. Multi-device editing of the same entity is an edge case (user edits a route title on phone, then edits description on tablet before syncing).

**Rules:**
1. `updated_at` is the authoritative timestamp
2. The version with the higher `updated_at` wins
3. If equal (clock skew): remote wins (conservative)
4. Field-level merges are NOT performed — the winning entity replaces the losing one entirely

```dart
Future<void> _resolveConflict(SyncQueueEntry local, RemoteEntity remote) async {
  final localTime  = local.payload['updated_at'] as int;
  final remoteTime = remote.updatedAt.millisecondsSinceEpoch;

  if (localTime > remoteTime) {
    // Local is newer — force push to remote
    await _forcePush(local);
  } else {
    // Remote is newer — discard local change, pull remote version
    await _applyRemoteVersion(remote);
    await db.syncQueue.delete(local.id);
    _notifyUser('A newer version of "${remote.title}" was downloaded.');
  }
}
```

### Conflict scenarios

| Scenario | Outcome |
|---|---|
| User edits route on phone, never syncs, edits again on same phone | Single queue entry (upsert) — no conflict |
| User edits route on phone, syncs, edits on tablet | Tablet pulls phone version, edits on top — clean |
| User edits on both devices while offline, both sync | LWW: whichever syncs second with higher `updated_at` wins |
| User deletes a route on phone, someone saves it on remote | Soft delete wins (deletion always propagates) |
| Track point stream interrupted mid-sync | Partitioned upload: each batch has sequence range; server deduplicates by (track_id, recorded_at) |

---

## 6. Pull: Remote → Local

After pushing, SyncService pulls changes for:
- Routes saved by the user (community stats may have updated)
- Routes published by users the current user follows
- Notification feed

```dart
Future<void> _pullRemoteChanges() async {
  final lastPull = await db.settings.get('last_pull_at') ?? 0;
  final now      = DateTime.now().millisecondsSinceEpoch;

  // Pull saved routes that were updated on remote since last pull
  final updatedRoutes = await supabase
      .from('routes')
      .select()
      .inFilter('id', await db.savedRoutes.getAllIds())
      .gt('updated_at', DateTime.fromMillisecondsSinceEpoch(lastPull).toIso8601String())
      .execute();

  for (final row in updatedRoutes.data) {
    await db.routes.upsertFromRemote(RouteMapper.fromJson(row));
    // Do NOT add to sync_queue — this is a pull, not a local write
  }

  await db.settings.set('last_pull_at', now);
}
```

**Pull does NOT write to sync_queue.** Only local user writes go in the queue.

---

## 7. Photo Sync

Photos require special handling: binary upload to Supabase Storage, then metadata record in DB.

```
Local write:
  1. Save photo to app documents directory
  2. Insert photos row (local) with upload_status = 'pending'
  3. Insert sync_queue entry with operation = 'photo_upload', priority = 3

SyncService photo handler:
  1. Read local file from path
  2. Generate thumbnail (300×300)
  3. Upload original to Supabase Storage: photos/{user_id}/{photo_id}.jpg
  4. Upload thumbnail:                    photos/{user_id}/{photo_id}_thumb.jpg
  5. Insert public.photos row with storage_path + url
  6. Update local photos.remote_url + upload_status = 'uploaded'
  7. Delete sync_queue entry
```

**Chunked upload for large photos:**

```dart
Future<void> _uploadPhoto(SyncQueueEntry entry) async {
  final photo    = await db.photos.getById(entry.entityId);
  final file     = File(photo.localPath);
  final fileSize = await file.length();

  if (fileSize > 5 * 1024 * 1024) { // > 5MB: compress first
    final compressed = await _compressImage(file, maxDimension: 2048, quality: 85);
    await _uploadFile(compressed, photo);
  } else {
    await _uploadFile(file, photo);
  }
}
```

---

## 8. Track Point Sync

Track points are the highest-volume data. Strategy:

1. **Full resolution kept locally forever** (user owns their raw data)
2. **Simplified track synced to remote** (Douglas-Peucker, epsilon=5m) for display
3. **Raw points synced in batches** only if user explicitly exports or if storage allows

```dart
Future<void> _syncTrack(SyncQueueEntry entry) async {
  final track  = await db.tracks.getById(entry.entityId);
  final points = await db.trackPoints.getByTrackId(track.id);

  // 1. Simplify path for cloud display
  final simplified = douglasPeucker(points, epsilon: 5.0);
  final encoded    = encodePolyline(simplified);

  // 2. Push track header
  await supabase.from('tracks').upsert({
    ...track.toRemoteJson(),
    'encoded_path': encoded,
  });

  // 3. Push raw points in pages of 1000
  for (final batch in points.chunked(1000)) {
    await supabase.from('track_points').upsert(
      batch.map((p) => p.toRemoteJson()).toList(),
      onConflict: 'track_id,recorded_at', // deduplication key
    );
  }
}
```

---

## 9. Offline Detection & Connectivity

```dart
class ConnectivityMonitor {
  final _controller = StreamController<bool>.broadcast();
  
  Stream<bool> get isOnline => _controller.stream;

  ConnectivityMonitor() {
    Connectivity().onConnectivityChanged.listen((result) {
      final online = result != ConnectivityResult.none;
      _controller.add(online);
      if (online) SyncService.instance.flush(); // trigger sync on reconnect
    });
  }

  // True only if reachable — avoids captive portals
  Future<bool> hasActualInternet() async {
    try {
      final result = await InternetAddress.lookup('tile.openfreemap.org');
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
```

---

## 10. Sync State UI

Every entity in the UI shows a sync badge:

| State | Badge | Meaning |
|---|---|---|
| `synced_at != null` | None | Synced — no badge shown |
| `synced_at == null`, queue entry exists | ☁ (clock) | Pending sync |
| Queue entry `attempt_count > 0` | ⚠ | Failed, retrying |
| Queue entry `attempt_count > 20` | ✕ | Dead — needs manual retry |

```dart
Widget syncBadge(SyncStatus status) => switch (status) {
  SyncStatus.synced  => const SizedBox.shrink(),
  SyncStatus.pending => const Icon(Icons.cloud_upload_outlined, size: 14, color: Colors.grey),
  SyncStatus.retrying => const Icon(Icons.sync_problem, size: 14, color: Colors.orange),
  SyncStatus.dead    => const Icon(Icons.cloud_off, size: 14, color: Colors.red),
};
```

---

## 11. GDPR: Data Export & Deletion

### Export (user-initiated)

```
User: Settings > Account > Export my data
  │
  ▼
SyncService pulls all user data to local if not already cached
  │
  ▼
Generate ZIP:
  ├── profile.json
  ├── activities/
  │     ├── {track_id}.gpx  (each activity as GPX)
  │     └── ...
  ├── routes/
  │     └── {route_id}.gpx
  └── photos/
        └── (original photos)
  │
  ▼
Share sheet (save to Files / send via email)
```

### Account deletion

```
User: Settings > Account > Delete Account
  │
[Confirmation dialog with 7-day grace period]
  │
  ▼
Local: clear all tables except sync_queue
  │
  ▼
Remote: 
  1. Set users.deleted_at = NOW()            -- soft delete
  2. Anonymize: set display_name = 'Deleted User', email = null
  3. Retain: routes (is_public ones remain with anonymized author)
  4. Delete:  tracks, track_points, photos, reviews
  5. Schedule: hard delete after 30 days     -- Supabase scheduled function
```

---

*Related: [DATA_SCHEMA.md](DATA_SCHEMA.md) — table definitions*
*Related: [API_DESIGN.md](API_DESIGN.md) — client API contracts*
