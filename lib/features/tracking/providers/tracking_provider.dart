import 'dart:async';
import 'package:drift/drift.dart' hide Index;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';

part 'tracking_provider.g.dart';

enum TrackingStatus { idle, recording, paused, finished }

final selectedActivityTypeProvider = StateProvider<String>((ref) => 'hike');

final trackingStatusProvider = StateProvider<TrackingStatus>((ref) => TrackingStatus.idle);

/// Route ID to follow during the current tracking session. Null = free tracking.
final plannedRouteIdProvider = StateProvider<String?>((ref) => null);

@riverpod
class TrackingNotifier extends _$TrackingNotifier {
  StreamSubscription<Position>? _positionSub;
  String? _currentTrackId;
  final _uuid = const Uuid();

  @override
  TrackingState build() => const TrackingState();

  Future<void> startRecording({required String activityType}) async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw Exception('Location permission denied');
    }

    _currentTrackId = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;

    final db = ref.read(appDatabaseProvider);
    await db.into(db.tracksTable).insert(
      TracksTableCompanion.insert(
        id:           _currentTrackId!,
        userId:       'local', // replaced with real user id after auth
        title:        _generateTitle(activityType),
        activityType: activityType,
        startedAt:    now,
        createdAt:    now,
        updatedAt:    now,
      ),
    );

    ref.read(trackingStatusProvider.notifier).state = TrackingStatus.recording;
    state = TrackingState(trackId: _currentTrackId, startedAt: DateTime.now());

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5, // meters — standard mode
      ),
    ).listen(_onPosition);
  }

  void _onPosition(Position position) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final db  = ref.read(appDatabaseProvider);

    db.into(db.trackPointsTable).insert(
      TrackPointsTableCompanion.insert(
        trackId:    _currentTrackId!,
        lat:        position.latitude,
        lon:        position.longitude,
        elevationM: Value(position.altitude),
        accuracyM:  Value(position.accuracy),
        speedMs:    Value(position.speed),
        bearingDeg: Value(position.heading),
        recordedAt: now,
      ),
    );

    final newPoint = TrackPoint(
      lat: position.latitude,
      lon: position.longitude,
      elevationM: position.altitude,
      recordedAt: DateTime.now(),
    );

    final updatedPoints = [...state.recentPoints, newPoint];
    final distanceDelta = state.recentPoints.isNotEmpty
        ? Geolocator.distanceBetween(
            state.recentPoints.last.lat, state.recentPoints.last.lon,
            newPoint.lat, newPoint.lon,
          )
        : 0.0;

    state = state.copyWith(
      recentPoints: updatedPoints.length > 500 ? updatedPoints.sublist(updatedPoints.length - 500) : updatedPoints,
      distanceM:    (state.distanceM ?? 0) + distanceDelta,
      lastPosition: position,
    );
  }

  Future<String?> stopRecording() async {
    await _positionSub?.cancel();
    _positionSub = null;

    final trackId = _currentTrackId;

    if (trackId != null) {
      try {
        final now = DateTime.now().millisecondsSinceEpoch;
        final db  = ref.read(appDatabaseProvider);
        await (db.update(db.tracksTable)..where((t) => t.id.equals(trackId))).write(
          TracksTableCompanion(
            status:     const Value('finished'),
            finishedAt: Value(now),
            durationS:  Value(state.elapsedSeconds),
            distanceM:  Value(state.distanceM),
            updatedAt:  Value(now),
          ),
        );
      } catch (_) {
        // DB unavailable (e.g. isolate closed after hot restart) — continue to reset state
      }
    }

    ref.read(trackingStatusProvider.notifier).state = TrackingStatus.idle;
    state = const TrackingState();
    _currentTrackId = null;

    return trackId;
  }

  String _generateTitle(String activityType) {
    final hour  = DateTime.now().hour;
    final part  = hour < 12 ? 'Morning' : hour < 17 ? 'Afternoon' : 'Evening';
    final type  = activityType[0].toUpperCase() + activityType.substring(1);
    return '$part $type';
  }
}

class TrackingState {
  const TrackingState({
    this.trackId,
    this.startedAt,
    this.lastPosition,
    this.recentPoints = const [],
    this.distanceM,
  });

  final String?   trackId;
  final DateTime? startedAt;
  final Position? lastPosition;
  final List<TrackPoint> recentPoints;
  final double?   distanceM;

  int get elapsedSeconds =>
      startedAt != null ? DateTime.now().difference(startedAt!).inSeconds : 0;

  double get elevationGainM {
    if (recentPoints.length < 2) return 0;
    double gain = 0;
    for (var i = 1; i < recentPoints.length; i++) {
      final delta = recentPoints[i].elevationM - recentPoints[i - 1].elevationM;
      if (delta > 0) gain += delta;
    }
    return gain;
  }

  TrackingState copyWith({
    String?   trackId,
    DateTime? startedAt,
    Position? lastPosition,
    List<TrackPoint>? recentPoints,
    double?   distanceM,
  }) => TrackingState(
    trackId:      trackId      ?? this.trackId,
    startedAt:    startedAt    ?? this.startedAt,
    lastPosition: lastPosition ?? this.lastPosition,
    recentPoints: recentPoints ?? this.recentPoints,
    distanceM:    distanceM    ?? this.distanceM,
  );
}

class TrackPoint {
  const TrackPoint({
    required this.lat,
    required this.lon,
    required this.elevationM,
    required this.recordedAt,
  });

  final double   lat;
  final double   lon;
  final double   elevationM;
  final DateTime recordedAt;
}
