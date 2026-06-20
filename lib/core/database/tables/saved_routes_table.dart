import 'package:drift/drift.dart';

class SavedRoutesTable extends Table {
  @override
  String get tableName => 'saved_routes';

  TextColumn  get userId   => text()();
  TextColumn  get routeId  => text()();
  IntColumn   get savedAt  => integer()();

  @override
  Set<Column> get primaryKey => {userId, routeId};
}
