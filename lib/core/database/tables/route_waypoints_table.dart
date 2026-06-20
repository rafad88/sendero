import 'package:drift/drift.dart';
import 'routes_table.dart';

class RouteWaypointsTable extends Table {
  @override
  String get tableName => 'route_waypoints';

  TextColumn  get id            => text()();
  TextColumn  get routeId       => text().references(RoutesTable, #id)();
  IntColumn   get sequence      => integer()();
  RealColumn  get lat           => real()();
  RealColumn  get lon           => real()();
  RealColumn  get elevationM    => real().nullable()();
  TextColumn  get title         => text()();
  TextColumn  get description   => text().nullable()();
  TextColumn  get waypointType  => text().withDefault(const Constant('generic'))();
  TextColumn  get photoUrl      => text().nullable()();
  IntColumn   get createdAt     => integer()();
  IntColumn   get updatedAt     => integer()();
  IntColumn   get syncedAt      => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
