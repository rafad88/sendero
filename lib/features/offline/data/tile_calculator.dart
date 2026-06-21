import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

class TileCoord {
  const TileCoord(this.z, this.x, this.y);
  final int z, x, y;

  String get path => '$z/$x/$y';
}

class TileCalculator {
  static int _latToTileY(double lat, int zoom) {
    final latRad = lat * math.pi / 180;
    final n = math.pow(2, zoom).toDouble();
    return ((1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) / 2.0 * n).floor();
  }

  static int _lonToTileX(double lon, int zoom) {
    final n = math.pow(2, zoom).toDouble();
    return ((lon + 180.0) / 360.0 * n).floor();
  }

  /// Returns all tiles covering [bounds] + [bufferTiles] padding at zoom levels [minZoom]..[maxZoom].
  static List<TileCoord> tilesForBounds({
    required double minLat,
    required double minLon,
    required double maxLat,
    required double maxLon,
    int minZoom = 10,
    int maxZoom = 16,
    int bufferTiles = 1,
  }) {
    final tiles = <TileCoord>[];

    for (var z = minZoom; z <= maxZoom; z++) {
      final xMin = (_lonToTileX(minLon, z) - bufferTiles).clamp(0, (1 << z) - 1);
      final xMax = (_lonToTileX(maxLon, z) + bufferTiles).clamp(0, (1 << z) - 1);
      // Note: y increases downward — minLat → higher y, maxLat → lower y
      final yMin = (_latToTileY(maxLat, z) - bufferTiles).clamp(0, (1 << z) - 1);
      final yMax = (_latToTileY(minLat, z) + bufferTiles).clamp(0, (1 << z) - 1);

      for (var x = xMin; x <= xMax; x++) {
        for (var y = yMin; y <= yMax; y++) {
          tiles.add(TileCoord(z, x, y));
        }
      }
    }

    return tiles;
  }

  /// Computes bounding box from a list of GPX points.
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
}
