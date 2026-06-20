# Sendero — API Design

**Version:** 0.1
**Date:** 2026-06-20

Sendero's backend is Supabase. The "API" is a combination of:
- **PostgREST** — auto-generated REST API from the Postgres schema
- **Supabase Edge Functions** — Deno functions for logic that can't live in PostgREST
- **Supabase Realtime** — WebSocket subscriptions for live features
- **Supabase Storage** — S3-compatible API for binary uploads

The Flutter client uses the `supabase_flutter` SDK, which wraps all of these.

---

## 1. Authentication

Handled entirely by Supabase Auth. The client SDK manages token storage and refresh.

```dart
// Sign up
await supabase.auth.signUp(email: email, password: password);

// OAuth
await supabase.auth.signInWithOAuth(OAuthProvider.google);
await supabase.auth.signInWithOAuth(OAuthProvider.apple);

// Sign in
await supabase.auth.signInWithPassword(email: email, password: password);

// Get current user JWT (auto-refreshed)
final session = supabase.auth.currentSession;
final jwt     = session?.accessToken;  // sent as Authorization: Bearer {jwt}
```

All PostgREST and Edge Function calls automatically include the JWT. RLS policies evaluate `auth.uid()` from the JWT.

---

## 2. Route Endpoints

### 2.1 Get routes near a location

**Client call:**
```dart
final routes = await supabase.rpc('routes_near', params: {
  'user_lat':       lat,
  'user_lon':       lon,
  'radius_m':       20000,
  'activity_type':  activityType,   // nullable
  'min_difficulty': minDifficulty,  // nullable
  'max_difficulty': maxDifficulty,  // nullable
  'min_distance_m': minDistance,    // nullable
  'max_distance_m': maxDistance,    // nullable
  'sort_by':        'distance',     // 'distance'|'rating'|'newest'
  'limit':          50,
  'offset':         0,
});
```

**Postgres function:**
```sql
CREATE OR REPLACE FUNCTION routes_near(
  user_lat       FLOAT,
  user_lon       FLOAT,
  radius_m       INTEGER DEFAULT 20000,
  activity_type  TEXT    DEFAULT NULL,
  min_difficulty INTEGER DEFAULT NULL,
  max_difficulty INTEGER DEFAULT NULL,
  min_distance_m FLOAT   DEFAULT NULL,
  max_distance_m FLOAT   DEFAULT NULL,
  sort_by        TEXT    DEFAULT 'distance',
  "limit"        INTEGER DEFAULT 50,
  "offset"       INTEGER DEFAULT 0
)
RETURNS TABLE (
  id                UUID,
  title             TEXT,
  activity_type     TEXT,
  difficulty        SMALLINT,
  distance_m        REAL,
  elevation_gain_m  REAL,
  avg_rating        REAL,
  review_count      INTEGER,
  save_count        INTEGER,
  encoded_path      TEXT,
  author_name       TEXT,
  author_avatar     TEXT,
  distance_from_user FLOAT,
  country_code      CHAR(2),
  locality          TEXT
)
LANGUAGE sql STABLE AS $$
  SELECT
    r.id, r.title, r.activity_type, r.difficulty,
    r.distance_m, r.elevation_gain_m,
    r.avg_rating, r.review_count, r.save_count,
    ST_AsEncodedPolyline(r.geom::geometry) AS encoded_path,
    u.display_name AS author_name,
    u.avatar_url   AS author_avatar,
    ST_Distance(r.start_point, ST_MakePoint(user_lon, user_lat)::geography) AS distance_from_user,
    r.country_code, r.locality
  FROM public.routes r
  JOIN public.users u ON u.id = r.author_id
  WHERE
    r.is_public = TRUE AND r.is_deleted = FALSE
    AND ST_DWithin(r.start_point, ST_MakePoint(user_lon, user_lat)::geography, radius_m)
    AND (activity_type   IS NULL OR r.activity_type   = activity_type)
    AND (min_difficulty  IS NULL OR r.difficulty      >= min_difficulty)
    AND (max_difficulty  IS NULL OR r.difficulty      <= max_difficulty)
    AND (min_distance_m  IS NULL OR r.distance_m      >= min_distance_m)
    AND (max_distance_m  IS NULL OR r.distance_m      <= max_distance_m)
  ORDER BY
    CASE sort_by
      WHEN 'distance' THEN ST_Distance(r.start_point, ST_MakePoint(user_lon, user_lat)::geography)
      WHEN 'rating'   THEN -COALESCE(r.avg_rating, 0)
      WHEN 'newest'   THEN EXTRACT(EPOCH FROM r.created_at) * -1
      ELSE ST_Distance(r.start_point, ST_MakePoint(user_lon, user_lat)::geography)
    END
  LIMIT "limit" OFFSET "offset";
$$;
```

### 2.2 Search routes by text

**Client call:**
```dart
final results = await supabase.rpc('search_routes', params: {
  'query': searchText,
  'limit': 20,
});
```

**Postgres function:**
```sql
CREATE OR REPLACE FUNCTION search_routes(query TEXT, "limit" INTEGER DEFAULT 20)
RETURNS TABLE (id UUID, title TEXT, activity_type TEXT, difficulty SMALLINT,
               distance_m REAL, avg_rating REAL, encoded_path TEXT, rank REAL)
LANGUAGE sql STABLE AS $$
  SELECT r.id, r.title, r.activity_type, r.difficulty,
         r.distance_m, r.avg_rating,
         ST_AsEncodedPolyline(r.geom::geometry),
         similarity(r.title, query) AS rank
  FROM public.routes r
  WHERE r.is_public AND NOT r.is_deleted AND r.title % query
  ORDER BY rank DESC, avg_rating DESC NULLS LAST
  LIMIT "limit";
$$;
```

### 2.3 Get route detail

```dart
final route = await supabase
    .from('routes')
    .select('''
      *,
      author:users(id, display_name, avatar_url, routes_published),
      waypoints:route_waypoints(* ORDER BY sequence ASC),
      photos:photos(id, url, thumbnail_url, caption ORDER BY sequence ASC),
      user_has_saved:saved_routes(route_id)
    ''')
    .eq('id', routeId)
    .single();
```

### 2.4 Create / update a route

```dart
// Upsert (handles both create and update)
await supabase.from('routes').upsert({
  'id':              route.id,
  'title':           route.title,
  'description':     route.description,
  'author_id':       currentUserId,
  'activity_type':   route.activityType,
  'difficulty':      route.difficulty,
  'geom':            route.encodedPath,   // Edge Function converts to PostGIS
  'distance_m':      route.distanceM,
  'elevation_gain_m': route.elevationGainM,
  'elevation_loss_m': route.elevationLossM,
  'is_public':       route.isPublic,
  'updated_at':      DateTime.now().toIso8601String(),
});
```

**Note:** The `geom` field is handled by an Edge Function (`process-route`) that converts the encoded polyline to a PostGIS geometry, computes bounding box, and reverse-geocodes the start point.

### 2.5 Edge Function: `process-route`

Triggered by a Postgres trigger on `routes` INSERT/UPDATE when `geom` changes.

```typescript
// supabase/functions/process-route/index.ts
import { serve } from 'https://deno.land/std/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js'
import { decode as decodePolyline } from './polyline.ts'
import { reverseGeocode } from './geocode.ts'

serve(async (req) => {
  const { route_id, encoded_path } = await req.json()
  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)

  const coords = decodePolyline(encoded_path)  // [[lat,lon], ...]
  
  // Build PostGIS LINESTRING
  const linestring = `LINESTRING(${coords.map(([lat, lon]) => `${lon} ${lat}`).join(',')})`

  // Reverse geocode the start point
  const [startLat, startLon] = coords[0]
  const geo = await reverseGeocode(startLat, startLon)

  await supabase.from('routes').update({
    geom:         `SRID=4326;${linestring}`,
    country_code: geo.countryCode,
    region:       geo.region,
    locality:     geo.locality,
  }).eq('id', route_id)

  return new Response('ok')
})
```

---

## 3. Track Endpoints

### 3.1 Sync a completed track

```dart
// Step 1: upsert track header
await supabase.from('tracks').upsert({
  'id':              track.id,
  'user_id':         track.userId,
  'route_id':        track.routeId,
  'title':           track.title,
  'activity_type':   track.activityType,
  'started_at':      track.startedAt.toIso8601String(),
  'finished_at':     track.finishedAt?.toIso8601String(),
  'duration_s':      track.durationS,
  'distance_m':      track.distanceM,
  'elevation_gain_m': track.elevationGainM,
  'elevation_loss_m': track.elevationLossM,
  'avg_speed_ms':    track.avgSpeedMs,
  'is_public':       track.isPublic,
  'geom':            track.simplifiedEncodedPath,
  'updated_at':      DateTime.now().toIso8601String(),
});

// Step 2: push raw points in batches
const batchSize = 1000;
for (var i = 0; i < points.length; i += batchSize) {
  final batch = points.sublist(i, min(i + batchSize, points.length));
  await supabase.from('track_points').upsert(
    batch.map((p) => {
      'track_id':   track.id,
      'recorded_at': DateTime.fromMillisecondsSinceEpoch(p.recordedAt).toIso8601String(),
      'lat':         p.lat,
      'lon':         p.lon,
      'elevation_m': p.elevationM,
      'accuracy_m':  p.accuracyM,
      'speed_ms':    p.speedMs,
    }).toList(),
    onConflict: 'track_id,recorded_at',
  );
}
```

### 3.2 Get activity feed

```dart
final feed = await supabase
    .from('tracks')
    .select('''
      id, title, activity_type, distance_m, elevation_gain_m,
      started_at, duration_s, is_public,
      user:users(id, display_name, avatar_url),
      route:routes(id, title)
    ''')
    .eq('is_public', true)
    .inFilter('user_id', followingIds)
    .order('started_at', ascending: false)
    .limit(30);
```

### 3.3 Export track as GPX (Edge Function)

```dart
final response = await supabase.functions.invoke('export-track', body: {
  'track_id': trackId,
  'format':   'gpx',      // 'gpx'|'fit'|'kml'
});
// Returns binary file content
```

```typescript
// supabase/functions/export-track/index.ts
serve(async (req) => {
  const { track_id, format } = await req.json()
  
  // Verify ownership via JWT
  const user = await getUser(req)
  const track = await fetchTrack(track_id)
  if (track.user_id !== user.id) return new Response('Forbidden', { status: 403 })
  
  const points = await fetchTrackPoints(track_id)  // full resolution

  if (format === 'gpx') {
    const gpx = buildGpx(track, points)
    return new Response(gpx, {
      headers: {
        'Content-Type': 'application/gpx+xml',
        'Content-Disposition': `attachment; filename="${track.title}.gpx"`,
      }
    })
  }
  // ... FIT, KML handlers
})
```

---

## 4. User Endpoints

### 4.1 Get user profile

```dart
final profile = await supabase
    .from('users')
    .select('''
      id, display_name, avatar_url, bio, units,
      total_distance_m, total_elevation_m, total_activities,
      routes_published, follower_count, following_count,
      is_following:follows!inner(follower_id)
    ''')
    .eq('id', userId)
    .single();
```

### 4.2 Follow / unfollow

```dart
// Follow
await supabase.from('follows').insert({
  'follower_id':  currentUserId,
  'following_id': targetUserId,
});

// Unfollow
await supabase.from('follows').delete()
    .eq('follower_id', currentUserId)
    .eq('following_id', targetUserId);
```

### 4.3 Update profile

```dart
await supabase.from('users').update({
  'display_name': displayName,
  'bio':          bio,
  'units':        units,
  'updated_at':   DateTime.now().toIso8601String(),
}).eq('auth_id', supabase.auth.currentUser!.id);
```

### 4.4 Upload avatar (Storage)

```dart
final bytes = await imageFile.readAsBytes();
final path  = 'avatars/${currentUserId}.jpg';

await supabase.storage.from('public').uploadBinary(
  path, bytes,
  fileOptions: FileOptions(contentType: 'image/jpeg', upsert: true),
);

final url = supabase.storage.from('public').getPublicUrl(path);

await supabase.from('users').update({'avatar_url': url})
    .eq('auth_id', supabase.auth.currentUser!.id);
```

---

## 5. Review Endpoints

### 5.1 Submit review

```dart
await supabase.from('reviews').upsert({
  'id':        reviewId,           // generated client-side (UUID)
  'route_id':  routeId,
  'user_id':   currentUserId,
  'rating':    rating,             // 1–5
  'body':      body,
  'track_id':  trackId,            // optional: link to the activity
  'visited_at': visitedAt?.toIso8601String(),
  'condition': condition,          // 'excellent'|'good'|'poor'|'closed'
}, onConflict: 'route_id,user_id');
```

### 5.2 Get reviews for a route

```dart
final reviews = await supabase
    .from('reviews')
    .select('''
      id, rating, body, visited_at, condition, created_at,
      user:users(id, display_name, avatar_url)
    ''')
    .eq('route_id', routeId)
    .order('created_at', ascending: false)
    .limit(20);
```

---

## 6. Photo Upload

```dart
Future<String> uploadPhoto(File file, String entityType, String entityId) async {
  final photoId  = const Uuid().v4();
  final path     = 'photos/$entityType/$entityId/$photoId.jpg';
  
  // Compress before upload
  final compressed = await FlutterImageCompress.compressWithFile(
    file.path, minWidth: 2048, minHeight: 2048, quality: 85,
  );

  await supabase.storage.from('photos').uploadBinary(
    path, compressed!,
    fileOptions: FileOptions(contentType: 'image/jpeg'),
  );

  final url = supabase.storage.from('photos').getPublicUrl(path);
  
  // Generate thumbnail via Edge Function
  await supabase.functions.invoke('generate-thumbnail', body: {'path': path});

  // Insert metadata record
  await supabase.from('photos').insert({
    'id':           photoId,
    'uploader_id':  currentUserId,
    'entity_type':  entityType,
    'entity_id':    entityId,
    'storage_path': path,
    'url':          url,
    'thumbnail_url': url.replaceAll('.jpg', '_thumb.jpg'),
  });

  return url;
}
```

---

## 7. Realtime Subscriptions

### 7.1 Live location sharing (v1.x)

```dart
// Publisher (leader device)
final channel = supabase.channel('group:$groupCode');

channel.subscribe();

// Send own position every 10 seconds
Timer.periodic(Duration(seconds: 10), (_) {
  channel.sendBroadcastMessage(event: 'position', payload: {
    'user_id':  currentUserId,
    'lat':      currentLat,
    'lon':      currentLon,
    'accuracy': accuracy,
    'ts':       DateTime.now().millisecondsSinceEpoch,
  });
});

// Receiver (other group members)
channel.onBroadcast(event: 'position', callback: (payload) {
  updateGroupMemberPosition(payload);
});
```

### 7.2 Sync notifications

```dart
// Subscribe to own user's data changes
supabase
    .from('tracks')
    .stream(primaryKey: ['id'])
    .eq('user_id', currentUserId)
    .listen((data) {
      // Update local UI when remote sync resolves
    });
```

---

## 8. Offline Map Tile Serving

Map tiles are **not** served through Supabase. They come from:
- **Online:** OpenFreeMap CDN (`https://tiles.openfreemap.org/planet/{z}/{x}/{y}.pbf`)
- **Offline:** Local `.pmtiles` file on device (MapLibre reads via file:// URI)

The tile source selection is handled by MapLibre's offline region management:

```dart
// Register a local tile source for offline use
final style = MapLibreStyle(
  sources: {
    'openmaptiles': VectorTileSource(
      tiles: isOffline
          ? ['file://${offlinePackage.tilePath}']
          : ['https://tiles.openfreemap.org/planet/{z}/{x}/{y}.pbf'],
    ),
  },
  // ... layer definitions
);
```

---

## 9. Rate Limits & Quotas

| Endpoint | Free tier limit | Explorer/Creator |
|---|---|---|
| `routes_near` | 60 req/min | 300 req/min |
| `search_routes` | 30 req/min | 150 req/min |
| Track point upload | 50k points/day | Unlimited |
| Photo upload | 1 GB total storage | 10 GB |
| GPX export | Unlimited | Unlimited |
| Offline regions | 3 packages | Unlimited |
| Realtime channels | 1 concurrent | 5 concurrent |

Limits enforced at Supabase edge via `pg_stat_statements` + custom rate-limit function.

---

## 10. Error Handling

All API errors follow a consistent shape:

```dart
class ApiError {
  final String code;       // 'NOT_FOUND'|'FORBIDDEN'|'RATE_LIMITED'|'CONFLICT'|...
  final String message;    // human-readable
  final String? detail;    // optional technical detail
}
```

Client error handling pattern:

```dart
try {
  await supabase.from('routes').upsert(data);
} on PostgrestException catch (e) {
  switch (e.code) {
    case '42501': throw ApiError('FORBIDDEN', 'Cannot edit this route');
    case '23505': throw ApiError('CONFLICT', 'Route already exists');
    default:      throw ApiError('SERVER_ERROR', e.message);
  }
} on StorageException catch (e) {
  throw ApiError('STORAGE_ERROR', 'Photo upload failed: ${e.message}');
}
```

---

*Related: [DATA_SCHEMA.md](DATA_SCHEMA.md) — table definitions*
*Related: [SYNC_PROTOCOL.md](SYNC_PROTOCOL.md) — offline sync architecture*
