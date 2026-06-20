import 'package:drift/drift.dart';

class PhotosTable extends Table {
  @override
  String get tableName => 'photos';

  TextColumn  get id            => text()();
  TextColumn  get entityType    => text()(); // 'track' | 'route' | 'waypoint'
  TextColumn  get entityId      => text()();
  TextColumn  get localPath     => text()();
  TextColumn  get remoteUrl     => text().nullable()();
  RealColumn  get lat           => real().nullable()();
  RealColumn  get lon           => real().nullable()();
  IntColumn   get takenAt       => integer().nullable()();
  IntColumn   get widthPx       => integer().nullable()();
  IntColumn   get heightPx      => integer().nullable()();
  IntColumn   get sizeBytes     => integer().nullable()();
  TextColumn  get caption       => text().nullable()();
  IntColumn   get sequence      => integer().withDefault(const Constant(0))();
  // 'pending' | 'uploading' | 'uploaded' | 'error'
  TextColumn  get uploadStatus  => text().withDefault(const Constant('pending'))();
  IntColumn   get createdAt     => integer()();
  IntColumn   get syncedAt      => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
