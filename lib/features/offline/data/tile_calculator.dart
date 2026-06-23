import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

class TileCoord {
  const TileCoord(this.z, this.x, this.y);
  final int z, x, y;

  String get path => '$z/$x/$y';

  @override
  bool operator ==(Object other) =>
      other is TileCoord && z == other.z && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(z, x, y);
}

class TileCalculator {
  static int _latToTileY(double lat, int zoom) {
    final latRad = lat * math.pi / 180;
    final n = math.pow(2, zoom).toDouble();
    return ((1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) / 2.0 * n)
        .floor()
        .clamp(0, (1 << zoom) - 1);
  }

  static int _lonToTileX(double lon, int zoom) {
    final n = math.pow(2, zoom).toDouble();
    return ((lon + 180.0) / 360.0 * n).floor().clamp(0, (1 << zoom) - 1);
  }

  /// Returns tiles within [bufferMeters] of any route point at zoom [minZoom]..[maxZoom].
  /// Samples the route every ~150 m to skip redundant points, then for each sample
  /// collects the rectangle of tiles that covers a [bufferMeters] radius square.
  static List<TileCoord> tilesForRoute({
    required List<LatLng> points,
    int minZoom = 12,
    int maxZoom = 16,
    double bufferMeters = 500,
  }) {
    if (points.isEmpty) return [];

    final sampled = _samplePoints(points, stepMeters: 150);
    final tiles = <TileCoord>{};

    for (final pt in sampled) {
      final dLat = bufferMeters / 111000;
      final dLon = bufferMeters / (111000 * math.cos(pt.latitude * math.pi / 180));

      for (var z = minZoom; z <= maxZoom; z++) {
        final xMin = _lonToTileX(pt.longitude - dLon, z);
        final xMax = _lonToTileX(pt.longitude + dLon, z);
        final yMin = _latToTileY(pt.latitude + dLat, z); // higher lat → lower y index
        final yMax = _latToTileY(pt.latitude - dLat, z);

        for (var x = xMin; x <= xMax; x++) {
          for (var y = yMin; y <= yMax; y++) {
            tiles.add(TileCoord(z, x, y));
          }
        }
      }
    }

    return tiles.toList();
  }

  /// Computes bounding box from a list of GPX points (used to store bbox in DB).
  static ({double minLat, double minLon, double maxLat, double maxLon}) boundsFromPoints(
      List<LatLng> points) {
    var minLat = double.infinity;
    var minLon = double.infinity;
    var maxLat = double.negativeInfinity;
    var maxLon = double.negativeInfinity;

    for (final p in points) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    return (minLat: minLat, minLon: minLon, maxLat: maxLat, maxLon: maxLon);
  }

  /// Samples [points] at roughly [stepMeters] intervals to reduce redundant tile lookups.
  static List<LatLng> _samplePoints(List<LatLng> points, {double stepMeters = 150}) {
    if (points.length <= 2) return points;

    final result = [points.first];
    double accumulated = 0;

    for (var i = 1; i < points.length; i++) {
      accumulated += _distanceMeters(points[i - 1], points[i]);
      if (accumulated >= stepMeters) {
        result.add(points[i]);
        accumulated = 0;
      }
    }

    if (result.last != points.last) result.add(points.last);
    return result;
  }

  static double _distanceMeters(LatLng a, LatLng b) {
    const R = 6371000.0;
    final dLat = (b.latitude  - a.latitude)  * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final s = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * R * math.atan2(math.sqrt(s), math.sqrt(1 - s));
  }
}
