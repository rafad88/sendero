import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpx/gpx.dart';
import 'package:latlong2/latlong.dart';

import '../data/app_route.dart';
import '../data/route_repository.dart';

export '../data/app_route.dart';
export '../data/route_repository.dart';

// ── RouteData (GPX-derived stats) ────────────────────────────────────────────

class RouteData {
  const RouteData({
    required this.points,
    required this.distanceKm,
    required this.elevationGainM,
    required this.elevationLossM,
    required this.estimatedTimeMin,
  });

  final List<LatLng> points;
  final double distanceKm;
  final int elevationGainM;
  final int elevationLossM;
  final int estimatedTimeMin;

  String get estimatedTimeLabel {
    final h = estimatedTimeMin ~/ 60;
    final m = estimatedTimeMin % 60;
    return h > 0 ? (m > 0 ? '${h}h ${m}m' : '${h}h') : '${m}m';
  }
}

const _difficultyMultiplier = {
  'Easy':     1.0,
  'Moderate': 1.2,
  'Hard':     1.45,
  'Expert':   1.75,
};

// ── Providers ─────────────────────────────────────────────────────────────────

/// All public routes from Supabase.
final routesProvider = FutureProvider<List<AppRoute>>((ref) {
  return ref.watch(routeRepositoryProvider).fetchRoutes();
});

/// Single route metadata by slug.
final routeBySlugProvider =
    FutureProvider.family<AppRoute?, String>((ref, slug) {
  return ref.watch(routeRepositoryProvider).fetchBySlug(slug);
});

/// GPX-parsed data for a route (points, elevation, distance, time).
final routeDataProvider =
    FutureProvider.family<RouteData, String>((ref, slug) async {
  final repo  = ref.watch(routeRepositoryProvider);
  final route = await repo.fetchBySlug(slug);

  if (route == null) {
    return const RouteData(
        points: [], distanceKm: 0, elevationGainM: 0,
        elevationLossM: 0, estimatedTimeMin: 0);
  }

  final raw    = await repo.loadGpx(route);
  final gpx    = GpxReader().fromString(raw);
  final trkpts = gpx.trks
      .expand((t) => t.trksegs)
      .expand((s) => s.trkpts)
      .where((p) => p.lat != null && p.lon != null)
      .toList();

  final points = trkpts.map((p) => LatLng(p.lat!, p.lon!)).toList();

  double distanceM = 0;
  for (var i = 1; i < points.length; i++) {
    distanceM += _haversineM(points[i - 1], points[i]);
  }

  double gainM = 0, lossM = 0;
  for (var i = 1; i < trkpts.length; i++) {
    final prev = trkpts[i - 1].ele;
    final curr = trkpts[i].ele;
    if (prev == null || curr == null) continue;
    final diff = curr - prev;
    if (diff > 0) gainM += diff;
    if (diff < 0) lossM += diff.abs();
  }

  final naismithMin =
      (distanceM / 1000 / 4 + gainM / 600) * 60;
  final multiplier =
      _difficultyMultiplier[route.difficultyLabel] ?? 1.0;

  return RouteData(
    points:           points,
    distanceKm:       double.parse((distanceM / 1000).toStringAsFixed(1)),
    elevationGainM:   gainM.round(),
    elevationLossM:   lossM.round(),
    estimatedTimeMin: (naismithMin * multiplier).round(),
  );
});

double _haversineM(LatLng a, LatLng b) {
  const r = 6371000.0;
  final dLat = _rad(b.latitude  - a.latitude);
  final dLon = _rad(b.longitude - a.longitude);
  final sinLat = math.sin(dLat / 2);
  final sinLon = math.sin(dLon / 2);
  final h = sinLat * sinLat +
      math.cos(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * sinLon * sinLon;
  return 2 * r * math.asin(math.sqrt(h));
}

double _rad(double deg) => deg * math.pi / 180;
