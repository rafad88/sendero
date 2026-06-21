import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/database/app_database.dart';
import '../data/offline_repository.dart';
import '../data/tile_calculator.dart';
import '../data/tile_downloader.dart';

// ── Download state ────────────────────────────────────────────────────────────

class DownloadState {
  const DownloadState({
    this.isDownloading = false,
    this.downloaded = 0,
    this.total = 0,
    this.sizeBytes = 0,
    this.error,
  });

  final bool isDownloading;
  final int downloaded;
  final int total;
  final int sizeBytes;
  final String? error;

  double get progress => total == 0 ? 0 : downloaded / total;

  DownloadState copyWith({
    bool? isDownloading,
    int? downloaded,
    int? total,
    int? sizeBytes,
    String? error,
  }) => DownloadState(
    isDownloading: isDownloading ?? this.isDownloading,
    downloaded:    downloaded    ?? this.downloaded,
    total:         total         ?? this.total,
    sizeBytes:     sizeBytes     ?? this.sizeBytes,
    error:         error,
  );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class OfflineNotifier extends StateNotifier<DownloadState> {
  OfflineNotifier(this._repo) : super(const DownloadState());

  final OfflineRepository _repo;
  final _downloader = TileDownloader();

  /// Returns true if this route has been fully downloaded.
  Future<bool> isDownloaded(String routeId) async {
    final pkg = await _repo.getByRouteId(routeId);
    return pkg?.status == 'ready';
  }

  Future<void> downloadRoute({
    required String routeId,
    required String routeName,
    required List<LatLng> points,
  }) async {
    if (state.isDownloading) return;

    final bounds = TileCalculator.boundsFromPoints(points);
    final tiles  = TileCalculator.tilesForBounds(
      minLat: bounds.minLat,
      minLon: bounds.minLon,
      maxLat: bounds.maxLat,
      maxLon: bounds.maxLon,
    );

    final tileDirPath = await TileDownloader.tileDirPath(routeId);
    final now         = DateTime.now().millisecondsSinceEpoch;

    // Insert/reset record
    await _repo.upsert(OfflinePackagesTableCompanion.insert(
      id:             routeId,
      name:           routeName,
      bboxMinLat:     bounds.minLat,
      bboxMinLon:     bounds.minLon,
      bboxMaxLat:     bounds.maxLat,
      bboxMaxLon:     bounds.maxLon,
      tilePath:       tileDirPath,
      sizeBytes:      0,
      tileSourceUrl:  'https://tile.openstreetmap.org',
      tileVersion:    '1',
      downloadProgress: const Value(0.0),
      createdAt:      now,
      updatedAt:      now,
    ));

    state = DownloadState(isDownloading: true, total: tiles.length);

    try {
      final totalBytes = await _downloader.downloadTiles(
        routeId: routeId,
        tiles: tiles,
        onProgress: (downloaded, total, bytes) {
          state = state.copyWith(
            downloaded: downloaded,
            total:      total,
            sizeBytes:  bytes,
          );
          _repo.updateProgress(routeId, downloaded / total);
        },
      );

      await _repo.markReady(routeId, totalBytes);
      state = const DownloadState();
    } catch (e) {
      await _repo.markError(routeId, e.toString());
      state = DownloadState(error: e.toString());
    }
  }

  Future<void> deleteRoute(String routeId) async {
    await _downloader.deleteTiles(routeId);
    await _repo.delete(routeId);
  }

  void cancel() {
    _downloader.cancel();
    state = const DownloadState();
  }
}

final offlineNotifierProvider =
    StateNotifierProvider<OfflineNotifier, DownloadState>(
  (ref) => OfflineNotifier(ref.watch(offlineRepositoryProvider)),
);

/// Stream of all downloaded offline packages.
final offlinePackagesProvider = StreamProvider<List<OfflinePackagesTableData>>((ref) {
  return ref.watch(offlineRepositoryProvider).watchAll();
});

/// Whether a specific route has been downloaded.
final routeDownloadedProvider =
    FutureProvider.family<bool, String>((ref, routeId) async {
  return ref.watch(offlineNotifierProvider.notifier).isDownloaded(routeId);
});
