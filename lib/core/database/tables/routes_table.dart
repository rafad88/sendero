import 'package:drift/drift.dart';

class RoutesTable extends Table {
  @override
  String get tableName => 'routes';

  TextColumn  get id                => text()();
  TextColumn  get title             => text()();
  TextColumn  get description       => text().nullable()();
  TextColumn  get authorId          => text()();
  TextColumn  get activityType      => text()();
  IntColumn   get difficulty        => integer()();
  TextColumn  get encodedPath       => text()();
  RealColumn  get bboxMinLat        => real()();
  RealColumn  get bboxMinLon        => real()();
  RealColumn  get bboxMaxLat        => real()();
  RealColumn  get bboxMaxLon        => real()();
  RealColumn  get distanceM         => real()();
  RealColumn  get elevationGainM    => real().withDefault(const Constant(0.0))();
  RealColumn  get elevationLossM    => real().withDefault(const Constant(0.0))();
  RealColumn  get minElevationM     => real().nullable()();
  RealColumn  get maxElevationM     => real().nullable()();
  IntColumn   get estimatedDurationS => integer().nullable()();
  TextColumn  get countryCode       => text().nullable()();
  TextColumn  get region            => text().nullable()();
  TextColumn  get locality          => text().nullable()();
  IntColumn   get isPublic          => integer().withDefault(const Constant(0))();
  IntColumn   get isDeleted         => integer().withDefault(const Constant(0))();
  IntColumn   get isDownloaded      => integer().withDefault(const Constant(0))();
  RealColumn  get cachedRating      => real().nullable()();
  IntColumn   get cachedReviewCount => integer().withDefault(const Constant(0))();
  IntColumn   get cachedSaveCount   => integer().withDefault(const Constant(0))();
  IntColumn   get createdAt         => integer()();
  IntColumn   get updatedAt         => integer()();
  IntColumn   get syncedAt          => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
