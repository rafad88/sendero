import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart' hide RouteData;
import 'package:latlong2/latlong.dart';

import '../../../core/config/env.dart';
import '../../../core/map/hybrid_tile_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../offline/providers/connectivity_provider.dart';
import '../../routes/data/app_route.dart';
import '../../routes/providers/route_provider.dart';
import '../../tracking/providers/tracking_provider.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _centerOnGPS();
  }

  Future<void> _centerOnGPS() async {
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted || !_mapReady) return;
      _mapController.move(LatLng(pos.latitude, pos.longitude), 15);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isTracking = ref.watch(trackingStatusProvider) == TrackingStatus.recording;
    final isOnline   = ref.watch(isOnlineProvider);

    // Build route start markers from Supabase routes
    final routesAV = ref.watch(routesProvider);
    final routeMarkers = <Marker>[];
    for (final route in routesAV.valueOrNull ?? <AppRoute>[]) {
      if (route.startLat != null && route.startLon != null) {
        routeMarkers.add(Marker(
          point: LatLng(route.startLat!, route.startLon!),
          width: 44,
          height: 44,
          child: GestureDetector(
            onTap: () => _showRouteSummary(context, route),
            child: const _RoutePin(),
          ),
        ));
      }
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(40.416775, -3.703790),
              initialZoom: 6,
              onMapReady: () {
                _mapReady = true;
                _centerOnGPS();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: Env.tileUrl,
                userAgentPackageName: 'app.sendero.sendero',
                tileProvider: HybridTileProvider(offlineRouteId: null),
              ),
              MarkerLayer(markers: routeMarkers),
              CurrentLocationLayer(),
            ],
          ),

          // Top search bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: GestureDetector(
                onTap: () => context.go('/explore'),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                  ),
                  child: const Row(
                    children: [
                      SizedBox(width: 16),
                      Icon(Icons.search),
                      SizedBox(width: 8),
                      Text('Search trails and routes...', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Offline indicator
          if (!isOnline)
            Positioned(
              top: 70,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade700,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off, color: Colors.white, size: 14),
                      SizedBox(width: 6),
                      Text('Modo offline', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),

          // Locate me button
          Positioned(
            right: 12,
            bottom: 100,
            child: FloatingActionButton.small(
              heroTag: 'locate',
              backgroundColor: Colors.white,
              foregroundColor: AppColors.forestGreen,
              onPressed: _centerOnGPS,
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'track',
        onPressed: () => isTracking ? context.go('/tracking') : _startTracking(context),
        icon: Icon(isTracking ? Icons.radio_button_on : Icons.play_arrow),
        label: Text(isTracking ? 'Recording...' : 'Start'),
        backgroundColor: isTracking ? Colors.red : AppColors.trailOrange,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  void _startTracking(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => const _PreSessionSheet(),
    );
  }

  void _showRouteSummary(BuildContext context, AppRoute route) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RouteSummarySheet(route: route),
    );
  }
}

// ── Trail pin marker ─────────────────────────────────────────────────────────

class _RoutePin extends StatelessWidget {
  const _RoutePin();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.forestGreen,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: const Icon(Icons.hiking, color: Colors.white, size: 22),
    );
  }
}

// ── Route summary bottom sheet ───────────────────────────────────────────────

class _RouteSummarySheet extends ConsumerWidget {
  const _RouteSummarySheet({required this.route});
  final AppRoute route;

  static const _difficultyColors = {
    'Easy':     Colors.green,
    'Moderate': Colors.orange,
    'Hard':     Colors.deepOrange,
    'Expert':   Colors.red,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color  = _difficultyColors[route.difficultyLabel] ?? Colors.grey;
    final dataAV = ref.watch(routeDataProvider(route.slug));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: Text(route.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              const Icon(Icons.star, size: 16, color: Colors.amber),
              const SizedBox(width: 2),
              Text(route.avgRating.toStringAsFixed(1),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(route.difficultyLabel,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(route.shape.label,
                    style: TextStyle(
                        color: Colors.grey.shade700, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          dataAV.when(
            loading: () =>
                const SizedBox(height: 20, child: LinearProgressIndicator()),
            error: (_, __) => const SizedBox.shrink(),
            data: (data) => Row(
              children: [
                _Stat(icon: Icons.straighten, label: '${data.distanceKm} km'),
                const SizedBox(width: 20),
                _Stat(icon: Icons.terrain, label: '+${data.elevationGainM} m'),
                const SizedBox(width: 20),
                _Stat(icon: Icons.schedule, label: data.estimatedTimeLabel),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    context.go('/explore/route/${route.slug}');
                  },
                  child: const Text('Ver ruta'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    context.go('/explore/route/${route.slug}');
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Iniciar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 14)),
      ],
    );
  }
}

// ── Pre-session sheet ────────────────────────────────────────────────────────

class _PreSessionSheet extends ConsumerWidget {
  const _PreSessionSheet();

  static const _activities = [
    ('hike', Icons.hiking,          'Hike'),
    ('bike', Icons.directions_bike, 'Bike'),
    ('run',  Icons.directions_run,  'Run'),
    ('ski',  Icons.downhill_skiing, 'Ski'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Activity type', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _activities.map(((String type, IconData icon, String label) rec) {
              return _ActivityChip(type: rec.$1, icon: rec.$2, label: rec.$3);
            }).toList(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/tracking');
            },
            child: const Text('Start Recording'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ActivityChip extends ConsumerWidget {
  const _ActivityChip({required this.type, required this.icon, required this.label});

  final String type;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedActivityTypeProvider) == type;
    return GestureDetector(
      onTap: () => ref.read(selectedActivityTypeProvider.notifier).state = type,
      child: Column(
        children: [
          CircleAvatar(
            backgroundColor: selected ? AppColors.trailOrange : Colors.grey.shade200,
            foregroundColor: selected ? Colors.white : Colors.grey.shade700,
            child: Icon(icon),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: selected ? AppColors.trailOrange : null)),
        ],
      ),
    );
  }
}
