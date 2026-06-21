import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';

class OfflineRepository {
  const OfflineRepository(this._db);
  final AppDatabase _db;

  Stream<List<OfflinePackagesTableData>> watchAll() =>
      _db.select(_db.offlinePackagesTable).watch();

  Future<OfflinePackagesTableData?> getByRouteId(String routeId) =>
      (_db.select(_db.offlinePackagesTable)
            ..where((t) => t.id.equals(routeId)))
          .getSingleOrNull();

  Future<void> upsert(OfflinePackagesTableCompanion entry) =>
      _db.into(_db.offlinePackagesTable).insertOnConflictUpdate(entry);

  Future<void> updateProgress(String id, double progress) =>
      (_db.update(_db.offlinePackagesTable)..where((t) => t.id.equals(id)))
          .write(OfflinePackagesTableCompanion(
            downloadProgress: Value(progress),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ));

  Future<void> markReady(String id, int sizeBytes) =>
      (_db.update(_db.offlinePackagesTable)..where((t) => t.id.equals(id)))
          .write(OfflinePackagesTableCompanion(
            status: const Value('ready'),
            downloadProgress: const Value(1.0),
            sizeBytes: Value(sizeBytes),
            downloadedAt: Value(DateTime.now().millisecondsSinceEpoch),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ));

  Future<void> markError(String id, String message) =>
      (_db.update(_db.offlinePackagesTable)..where((t) => t.id.equals(id)))
          .write(OfflinePackagesTableCompanion(
            status: const Value('error'),
            errorMessage: Value(message),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ));

  Future<void> delete(String id) =>
      (_db.delete(_db.offlinePackagesTable)..where((t) => t.id.equals(id)))
          .go();
}

final offlineRepositoryProvider = Provider<OfflineRepository>(
  (ref) => OfflineRepository(ref.watch(appDatabaseProvider)),
);
