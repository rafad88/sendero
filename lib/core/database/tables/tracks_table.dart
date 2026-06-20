import 'package:drift/drift.dart';

class TracksTable extends Table {
  @override
  String get tableName => 'tracks';

  TextColumn  get id              => text()();
  TextColumn  get userId          => text()();
  TextColumn  get routeId         => text().nullable()();
  TextColumn  get title           => text()();
  TextColumn  get description     => text().nullable()();
  TextColumn  get activityType    => text()();
  IntColumn   get startedAt       => integer()();
  IntColumn   get finishedAt      => integer().nullable()();
  IntColumn   get durationS       => integer().nullable()();
  RealColumn  get distanceM       => real().nullable()();
  RealColumn  get elevationGainM  => real().nullable()();
  RealColumn  get elevationLossM  => real().nullable()();
  RealColumn  get avgSpeedMs      => real().nullable()();
  RealColumn  get maxSpeedMs      => real().nullable()();
  IntColumn   get avgHeartRate    => integer().nullable()();
  IntColumn   get maxHeartRate    => integer().nullable()();
  IntColumn   get calories        => integer().nullable()();
  // 'recording' | 'paused' | 'finished' | 'deleted'
  TextColumn  get status          => text().withDefault(const Constant('recording'))();
  IntColumn   get isPublic        => integer().withDefault(const Constant(0))();
  TextColumn  get encodedPath     => text().nullable()();
  RealColumn  get bboxMinLat      => real().nullable()();
  RealColumn  get bboxMinLon      => real().nullable()();
  RealColumn  get bboxMaxLat      => real().nullable()();
  RealColumn  get bboxMaxLon      => real().nullable()();
  IntColumn   get createdAt       => integer()();
  IntColumn   get updatedAt       => integer()();
  IntColumn   get syncedAt        => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
