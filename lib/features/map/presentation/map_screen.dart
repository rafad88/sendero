import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../tracking/providers/tracking_provider.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    final isTracking = ref.watch(trackingStatusProvider) == TrackingStatus.recording;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(40.416775, -3.703790),
              initialZoom: 12,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'app.sendero.sendero',
              ),
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

          // Locate me button
          Positioned(
            right: 12,
            bottom: 100,
            child: FloatingActionButton.small(
              heroTag: 'locate',
              backgroundColor: Colors.white,
              foregroundColor: AppColors.forestGreen,
              onPressed: _locateMe,
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

  void _locateMe() {
    // Will center on current location once geolocator provides a fix
  }

  void _startTracking(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => const _PreSessionSheet(),
    );
  }
}

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
