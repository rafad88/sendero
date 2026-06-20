import 'package:drift/drift.dart';
import 'tracks_table.dart';

class TrackPointsTable extends Table {
  @override
  String get tableName => 'track_points';

  IntColumn   get id              => integer().autoIncrement()();
  TextColumn  get trackId         => text().references(TracksTable, #id)();
  RealColumn  get lat             => real()();
  RealColumn  get lon             => real()();
  RealColumn  get elevationM      => real().nullable()();
  TextColumn  get elevationSource => text().nullable()(); // 'gps' | 'srtm'
  RealColumn  get accuracyM       => real().nullable()();
  RealColumn  get speedMs         => real().nullable()();
  RealColumn  get bearingDeg      => real().nullable()();
  IntColumn   get heartRate       => integer().nullable()();
  IntColumn   get recordedAt      => integer()(); // Unix ms
  IntColumn   get isFiltered      => integer().withDefault(const Constant(0))();
}
