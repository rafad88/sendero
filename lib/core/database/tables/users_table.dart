import 'package:drift/drift.dart';

class UsersTable extends Table {
  @override
  String get tableName => 'users';

  TextColumn  get id            => text()();
  TextColumn  get email         => text()();
  TextColumn  get displayName   => text()();
  TextColumn  get avatarUrl     => text().nullable()();
  TextColumn  get bio           => text().nullable()();
  TextColumn  get units         => text().withDefault(const Constant('metric'))();
  TextColumn  get gpsMode       => text().withDefault(const Constant('standard'))();
  TextColumn  get language      => text().withDefault(const Constant('en'))();
  IntColumn   get isPremium     => integer().withDefault(const Constant(0))();
  IntColumn   get premiumUntil  => integer().nullable()();
  IntColumn   get createdAt     => integer()();
  IntColumn   get updatedAt     => integer()();
  IntColumn   get syncedAt      => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
