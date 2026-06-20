import 'package:drift/drift.dart';

class SyncQueueTable extends Table {
  @override
  String get tableName => 'sync_queue';

  IntColumn   get id          => integer().autoIncrement()();
  TextColumn  get entityType  => text()();   // 'route'|'track'|'waypoint'|'photo'|...
  TextColumn  get entityId    => text()();
  TextColumn  get operation   => text()();   // 'upsert' | 'delete' | 'photo_upload'
  TextColumn  get payload     => text()();   // JSON
  IntColumn   get priority    => integer().withDefault(const Constant(5))();
  IntColumn   get attemptCount => integer().withDefault(const Constant(0))();
  TextColumn  get lastError   => text().nullable()();
  IntColumn   get nextRetryAt => integer().nullable()();
  IntColumn   get createdAt   => integer()();
}
