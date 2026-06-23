import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/config/env.dart';
import 'tile_calculator.dart';

typedef ProgressCallback = void Function(int downloaded, int total, int bytes);

class TileDownloader {
  static const _concurrency = 4;

  bool _cancelled = false;

  void cancel() => _cancelled = true;

  /// Downloads [tiles] and saves them under [tilesDir].
  /// Calls [onProgress] after each tile with (downloaded, total, cumulativeBytes).
  Future<int> downloadTiles({
    required String routeId,
    required List<TileCoord> tiles,
    required ProgressCallback onProgress,
  }) async {
    _cancelled = false;

    final dir = await _tilesDir(routeId);
    await dir.create(recursive: true);

    int downloaded = 0;
    int totalBytes = 0;
    final total = tiles.length;
    final client = http.Client();

    try {
      for (var i = 0; i < tiles.length; i += _concurrency) {
        if (_cancelled) break;

        final batch = tiles.skip(i).take(_concurrency).toList();
        final results = await Future.wait(
          batch.map((t) => _downloadTile(client, dir, t)),
        );

        for (final bytes in results) {
          downloaded++;
          totalBytes += bytes;
        }

        onProgress(downloaded, total, totalBytes);
      }
    } finally {
      client.close();
    }

    return totalBytes;
  }

  Future<int> _downloadTile(http.Client client, Directory dir, TileCoord t) async {
    final file = File(p.join(dir.path, '${t.z}_${t.x}_${t.y}.png'));
    if (await file.exists()) {
      final size = await file.length();
      return size;
    }

    try {
      final url = Env.tileUrl
          .replaceAll('{z}', '${t.z}')
          .replaceAll('{x}', '${t.x}')
          .replaceAll('{y}', '${t.y}');
      final response = await client.get(
        Uri.parse(url),
        headers: {'User-Agent': 'Sendero/1.0 (offline map download)'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        return response.bodyBytes.length;
      }
    } catch (_) {
      // Skip failed tiles — non-fatal
    }
    return 0;
  }

  Future<void> deleteTiles(String routeId) async {
    final dir = await _tilesDir(routeId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<int> sizeBytes(String routeId) async {
    final dir = await _tilesDir(routeId);
    if (!await dir.exists()) return 0;

    int total = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  static Future<Directory> _tilesDir(String routeId) async {
    final base = await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, 'offline', 'tiles', routeId));
  }

  static Future<String> tileDirPath(String routeId) async {
    final dir = await _tilesDir(routeId);
    return dir.path;
  }
}
