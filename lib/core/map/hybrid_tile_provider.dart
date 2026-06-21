import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Serves tiles from disk when available, network otherwise.
/// Caches downloaded network tiles to disk for future offline use.
class HybridTileProvider extends TileProvider {
  HybridTileProvider({required this.offlineRouteId, super.headers});

  final String? offlineRouteId;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _HybridImage(
      networkUrl: getTileUrl(coordinates, options),
      routeId: offlineRouteId,
      z: coordinates.z,
      x: coordinates.x,
      y: coordinates.y,
      headers: headers,
    );
  }
}

@immutable
class _HybridImage extends ImageProvider<_HybridImage> {
  const _HybridImage({
    required this.networkUrl,
    required this.routeId,
    required this.z,
    required this.x,
    required this.y,
    required this.headers,
  });

  final String networkUrl;
  final String? routeId;
  final int z, x, y;
  final Map<String, String> headers;

  @override
  Future<_HybridImage> obtainKey(ImageConfiguration config) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_HybridImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _load(decode),
      scale: 1.0,
      debugLabel: networkUrl,
    );
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    Uint8List? bytes;

    // 1 — try local file
    if (routeId != null) {
      final file = await _localFile(routeId!);
      if (await file.exists()) {
        bytes = await file.readAsBytes();
      }
    }

    // 2 — network fallback
    if (bytes == null) {
      try {
        final response = await http.get(
          Uri.parse(networkUrl),
          headers: {...headers, 'User-Agent': 'Sendero/1.0'},
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          bytes = response.bodyBytes;

          // Cache to disk if we have a route context
          if (routeId != null) {
            try {
              final file = await _localFile(routeId!, create: true);
              await file.writeAsBytes(bytes);
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    bytes ??= _transparentPng;
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  Future<File> _localFile(String id, {bool create = false}) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'offline', 'tiles', id));
    if (create) await dir.create(recursive: true);
    return File(p.join(dir.path, '${z}_${x}_${y}.png'));
  }

  @override
  bool operator ==(Object other) =>
      other is _HybridImage &&
      networkUrl == other.networkUrl &&
      routeId == other.routeId;

  @override
  int get hashCode => Object.hash(networkUrl, routeId);

  static final _transparentPng = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);
}
