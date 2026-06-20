import 'package:drift/drift.dart';

class OfflinePackagesTable extends Table {
  @override
  String get tableName => 'offline_packages';

  TextColumn  get id                => text()();
  TextColumn  get name              => text()();
  RealColumn  get bboxMinLat        => real()();
  RealColumn  get bboxMinLon        => real()();
  RealColumn  get bboxMaxLat        => real()();
  RealColumn  get bboxMaxLon        => real()();
  TextColumn  get tilePath          => text().unique()();
  IntColumn   get sizeBytes         => integer()();
  TextColumn  get tileSourceUrl     => text()();
  TextColumn  get tileVersion       => text()();
  // 'downloading' | 'ready' | 'updating' | 'error'
  TextColumn  get status            => text().withDefault(const Constant('downloading'))();
  RealColumn  get downloadProgress  => real().nullable()();
  TextColumn  get errorMessage      => text().nullable()();
  IntColumn   get downloadedAt      => integer().nullable()();
  IntColumn   get expiresAt         => integer().nullable()();
  IntColumn   get createdAt         => integer()();
  IntColumn   get updatedAt         => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
