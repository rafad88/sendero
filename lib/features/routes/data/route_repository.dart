import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_route.dart';

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
