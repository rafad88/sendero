import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpx/gpx.dart';
import 'package:latlong2/latlong.dart';

import '../data/local_routes.dart';

export '../data/local_routes.dart';

class RouteData {
  const RouteData({
    required this.points,
    required this.distanceKm,
    required this.elevationGainM,
    required this.estimatedTimeMin,
  });

  final List<LatLng> points;
  final double distanceKm;
  final int elevationGainM;
  final int estimatedTimeMin;

  String get estimatedTimeLabel {
    final h = estimatedTimeMin ~/ 60;
    final m = estimatedTimeMin % 60;
    return h > 0 ? (m > 0 ? '${h}h ${m}m' : '${h}h') : '${m}m';
  }
}

// Difficulty multipliers applied on top of Naismith's rule.
// Hard terrain, exposure and route-finding all add time beyond pure fitness.
const _difficultyMultiplier = {
  'Easy':     1.0,
  'Moderate': 1.2,
  'Hard':     1.45,
  'Expert':   1.75,
};

final routeDataProvider = FutureProvider.family<RouteData, String>((ref, routeId) async {
  final route = routeById(routeId);
  if (route == null) return const RouteData(points: [], distanceKm: 0, elevationGainM: 0, estimatedTimeMin: 0);

  final raw = await rootBundle.loadString(route.gpxAsset);
  final gpx = GpxReader().fromString(raw);

  final trkpts = gpx.trks
      .expand((t) => t.trksegs)
      .expand((s) => s.trkpts)
      .where((p) => p.lat != null && p.lon != null)
      .toList();

  final points = trkpts.map((p) => LatLng(p.lat!, p.lon!)).toList();

  // Distance via Haversine
  double distanceM = 0;
  for (var i = 1; i < points.length; i++) {
    distanceM += _haversineM(points[i - 1], points[i]);
  }

  // Elevation gain (sum of positive ascent only)
  double gainM = 0;
  for (var i = 1; i < trkpts.length; i++) {
    final prev = trkpts[i - 1].ele;
    final curr = trkpts[i].ele;
    if (prev != null && curr != null && curr > prev) {
      gainM += curr - prev;
    }
  }

  // Naismith's rule: 1h per 4 km + 1h per 600 m gain
  final naismithMin = (distanceM / 1000 / 4 + gainM / 600) * 60;
  final multiplier  = _difficultyMultiplier[route.difficulty] ?? 1.0;
  final totalMin    = (naismithMin * multiplier).round();

  return RouteData(
    points:           points,
    distanceKm:       double.parse((distanceM / 1000).toStringAsFixed(1)),
    elevationGainM:   gainM.round(),
    estimatedTimeMin: totalMin,
  );
});

// Haversine distance in metres between two LatLng points
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
