import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_route.dart';

export 'app_route.dart';

class RouteRepository {
  const RouteRepository(this._db);
  final SupabaseClient _db;

  Future<List<AppRoute>> fetchRoutes() async {
    final data = await _db
        .from('routes')
        .select()
        .eq('is_public', true)
        .eq('is_deleted', false)
        .order('avg_rating', ascending: false);

    return (data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(AppRoute.fromSupabase)
        .toList();
  }

  Future<AppRoute?> fetchBySlug(String slug) async {
    final data = await _db
        .from('routes')
        .select()
        .eq('slug', slug)
        .maybeSingle();

    return data == null ? null : AppRoute.fromSupabase(data);
  }

  Future<void> createRoute({
    required String slug,
    required String title,
    required String activityType,
    required int difficulty,
    required RouteShape shape,
    required String gpxPath,
    required double distanceM,
    required double elevationGainM,
    required double elevationLossM,
    required double startLat,
    required double startLon,
    required double bboxMinLat,
    required double bboxMinLon,
    required double bboxMaxLat,
    required double bboxMaxLon,
    required String authorId,
    String? description,
  }) async {
    await _db.from('routes').insert({
      'slug':              slug,
      'title':             title,
      'description':       description,
      'author_id':         authorId,
      'activity_type':     activityType,
      'difficulty':        difficulty,
      'shape':             shape.name,
      'gpx_path':          gpxPath,
      'start_lat':         startLat,
      'start_lon':         startLon,
      'distance_m':        distanceM,
      'elevation_gain_m':  elevationGainM,
      'elevation_loss_m':  elevationLossM,
      'bbox_min_lat':      bboxMinLat,
      'bbox_min_lon':      bboxMinLon,
      'bbox_max_lat':      bboxMaxLat,
      'bbox_max_lon':      bboxMaxLon,
      'is_public':         true,
    });
  }

  /// Downloads GPX from Supabase Storage.
  Future<String> loadGpx(AppRoute route) async {
    if (route.gpxPath == null) {
      throw Exception('Route ${route.slug} has no GPX file in Storage');
    }
    final bytes = await _db.storage
        .from('gpx-files')
        .download(route.gpxPath!);
    return String.fromCharCodes(bytes);
  }
}

final routeRepositoryProvider = Provider<RouteRepository>(
  (ref) => RouteRepository(Supabase.instance.client),
);
