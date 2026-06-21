import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/tracking_provider.dart';

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  final MapController _mapController = MapController();
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final status = ref.read(trackingStatusProvider);
      if (status == TrackingStatus.idle) {
        final activityType = ref.read(selectedActivityTypeProvider);
        ref.read(trackingNotifierProvider.notifier).startRecording(activityType: activityType);
      }
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tracking = ref.watch(trackingNotifierProvider);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(40.416775, -3.703790),
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'app.sendero.sendero',
              ),
              CurrentLocationLayer(),
              if (tracking.recentPoints.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: tracking.recentPoints
                          .map((p) => LatLng(p.lat, p.lon))
                          .toList(),
                      color: AppColors.trailOrange,
                      strokeWidth: 4,
                    ),
                  ],
                ),
            ],
          ),

          SafeArea(
            child: Column(
              children: [_StatsBar(tracking: tracking)],
            ),
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _ControlBar(onStop: () => _confirmStop(context)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmStop(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Stop recording?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Stop')),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final trackId = await ref.read(trackingNotifierProvider.notifier).stopRecording();
      if (mounted) context.go('/tracking/save', extra: trackId);
    }
  }
}

class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.tracking});
  final TrackingState tracking;

  @override
  Widget build(BuildContext context) {
    final elapsed  = tracking.elapsedSeconds;
    final hours    = elapsed ~/ 3600;
    final minutes  = (elapsed % 3600) ~/ 60;
    final seconds  = elapsed % 60;
    final timeStr  = hours > 0
        ? '${hours}h ${minutes.toString().padLeft(2, '0')}m'
        : '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    final distKm   = ((tracking.distanceM ?? 0) / 1000).toStringAsFixed(2);
    final elevM    = tracking.elevationGainM.toStringAsFixed(0);

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(191),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Stat(label: 'Distance', value: '$distKm km'),
          _Stat(label: 'Time',     value: timeStr),
          _Stat(label: 'Elevation', value: '+$elevM m'),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: Colors.white.withAlpha(178), fontSize: 12)),
      ],
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({required this.onStop});
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton.filled(
            onPressed: () {},
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Add waypoint',
            style: IconButton.styleFrom(backgroundColor: AppColors.forestGreen, foregroundColor: Colors.white),
          ),
          FloatingActionButton.large(
            onPressed: onStop,
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            child: const Icon(Icons.stop, size: 36),
          ),
          IconButton.filled(
            onPressed: () {},
            icon: const Icon(Icons.photo_camera_outlined),
            tooltip: 'Add photo',
            style: IconButton.styleFrom(backgroundColor: AppColors.forestGreen, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }
}
