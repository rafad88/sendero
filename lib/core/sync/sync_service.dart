import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide Index;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

import '../database/app_database.dart';

part 'sync_service.g.dart';

// Backoff in seconds: attempt -> delay
const _backoffSeconds = [30, 120, 600, 1800, 7200, 21600, 86400];

int _nextRetryAfterSeconds(int attemptCount) {
  final idx = (attemptCount - 1).clamp(0, _backoffSeconds.length - 1);
  return _backoffSeconds[idx];
}

@riverpod
SyncService syncService(SyncServiceRef ref) {
  return SyncService(ref.watch(appDatabaseProvider));
}

class SyncService {
  SyncService(this._db);

  final AppDatabase _db;
  final _supabase = Supabase.instance.client;
  bool _isFlushing = false;

  Future<void> flush() async {
    if (_isFlushing) return;
    if (!await InternetConnection().hasInternetAccess) return;

    _isFlushing = true;
    try {
      await _pushPending();
    } finally {
      _isFlushing = false;
    }
  }

  Future<void> _pushPending() async {
    final now     = DateTime.now().millisecondsSinceEpoch;
    final pending = await (_db.select(_db.syncQueueTable)
          ..where((t) => t.nextRetryAt.isNull() | t.nextRetryAt.isSmallerOrEqualValue(now))
          ..orderBy([
            (t) => OrderingTerm(expression: t.priority),
            (t) => OrderingTerm(expression: t.id),
          ]))
        .get();

    for (final entry in pending) {
      try {
        await _dispatch(entry);
        await (_db.delete(_db.syncQueueTable)..where((t) => t.id.equals(entry.id))).go();
      } catch (e) {
        final newCount     = entry.attemptCount + 1;
        final delaySecs    = _nextRetryAfterSeconds(newCount);
        final nextRetryAt  = DateTime.now().millisecondsSinceEpoch + delaySecs * 1000;

        await (_db.update(_db.syncQueueTable)..where((t) => t.id.equals(entry.id))).write(
          SyncQueueTableCompanion(
            attemptCount: Value(newCount),
            lastError:    Value(e.toString()),
            nextRetryAt:  Value(nextRetryAt),
          ),
        );

        // Stop processing on network errors to avoid hammering
        if (e is SocketException || e.toString().contains('network')) break;
      }
    }
  }

  Future<void> _dispatch(SyncQueueTableData entry) async {
    final payload = jsonDecode(entry.payload) as Map<String, dynamic>;
    switch (entry.entityType) {
      case 'route':   await _syncRoute(payload);
      case 'track':   await _syncTrack(entry.entityId);
      case 'photo':   await _syncPhoto(entry.entityId);
      case 'review':  await _syncReview(payload);
      default: throw Exception('Unknown entity type: ${entry.entityType}');
    }
  }

  Future<void> _syncRoute(Map<String, dynamic> payload) async {
    await _supabase.from('routes').upsert(payload);
  }

  Future<void> _syncTrack(String trackId) async {
    final track = await (_db.select(_db.tracksTable)
          ..where((t) => t.id.equals(trackId)))
        .getSingleOrNull();
    if (track == null) return;

    await _supabase.from('tracks').upsert({
      'id':              track.id,
      'user_id':         track.userId,
      'route_id':        track.routeId,
      'title':           track.title,
      'activity_type':   track.activityType,
      'started_at':      DateTime.fromMillisecondsSinceEpoch(track.startedAt).toIso8601String(),
      'finished_at':     track.finishedAt != null
          ? DateTime.fromMillisecondsSinceEpoch(track.finishedAt!).toIso8601String()
          : null,
      'duration_s':      track.durationS,
      'distance_m':      track.distanceM,
      'elevation_gain_m': track.elevationGainM,
      'is_public':       track.isPublic == 1,
      'updated_at':      DateTime.now().toIso8601String(),
    });

    // Push raw points in batches of 1000
    const batchSize = 1000;
    var offset = 0;
    while (true) {
      final points = await (_db.select(_db.trackPointsTable)
            ..where((t) => t.trackId.equals(trackId))
            ..orderBy([(t) => OrderingTerm(expression: t.recordedAt)])
            ..limit(batchSize, offset: offset))
          .get();
      if (points.isEmpty) break;

      await _supabase.from('track_points').upsert(
        points.map((p) => {
          'track_id':    p.trackId,
          'recorded_at': DateTime.fromMillisecondsSinceEpoch(p.recordedAt).toIso8601String(),
          'lat':         p.lat,
          'lon':         p.lon,
          'elevation_m': p.elevationM,
          'accuracy_m':  p.accuracyM,
          'speed_ms':    p.speedMs,
        }).toList(),
        onConflict: 'track_id,recorded_at',
      );
      offset += batchSize;
      if (points.length < batchSize) break;
    }

    // Mark as synced
    await (_db.update(_db.tracksTable)..where((t) => t.id.equals(trackId))).write(
      TracksTableCompanion(syncedAt: Value(DateTime.now().millisecondsSinceEpoch)),
    );
  }

  Future<void> _syncPhoto(String photoId) async {
    // Photo binary upload is handled separately via StorageService
    // This entry updates the DB record after upload completes
    final photo = await (_db.select(_db.photosTable)
          ..where((t) => t.id.equals(photoId)))
        .getSingleOrNull();
    if (photo == null || photo.remoteUrl == null) return;

    await _supabase.from('photos').upsert({
      'id':           photo.id,
      'uploader_id':  photo.entityId,
      'entity_type':  photo.entityType,
      'entity_id':    photo.entityId,
      'storage_path': photo.remoteUrl,
      'url':          photo.remoteUrl,
      'caption':      photo.caption,
      'sequence':     photo.sequence,
    });
  }

  Future<void> _syncReview(Map<String, dynamic> payload) async {
    await _supabase.from('reviews').upsert(
      payload,
      onConflict: 'route_id,user_id',
    );
  }

  /// Enqueue a local entity for sync.
  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
    int priority = 5,
  }) async {
    await _db.into(_db.syncQueueTable).insert(
      SyncQueueTableCompanion.insert(
        entityType: entityType,
        entityId:   entityId,
        operation:  operation,
        payload:    jsonEncode(payload),
        priority:   Value(priority),
        createdAt:  DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}
