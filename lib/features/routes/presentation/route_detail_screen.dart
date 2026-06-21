import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart' hide RouteData;
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/route_provider.dart';
import 'explore_screen.dart' show routeShapeIcon;

class RouteDetailScreen extends ConsumerWidget {
  const RouteDetailScreen({required this.routeId, super.key});
  final String routeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route  = routeById(routeId);
    final dataAV = ref.watch(routeDataProvider(routeId));

    if (route == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Route not found')),
      );
    }

    void openMap(List<LatLng> points) => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullscreenRouteMap(name: route.name, points: points),
      ),
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(route.name),
              background: dataAV.when(
                loading: () => Container(
                  color: AppColors.forestGreen.withOpacity(0.2),
                  child: const Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => Container(color: AppColors.forestGreen.withOpacity(0.2)),
                data: (data) => data.points.isEmpty
                    ? Container(color: AppColors.forestGreen.withOpacity(0.2))
                    : _RouteMapPreview(points: data.points),
              ),
            ),
            // Fullscreen button in the app bar — avoids CustomScrollView swallowing taps
            actions: [
              dataAV.maybeWhen(
                data: (data) => data.points.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        icon: const Icon(Icons.fullscreen),
                        tooltip: 'Full map',
                        onPressed: () => openMap(data.points),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
              IconButton(icon: const Icon(Icons.bookmark_outline), onPressed: () {}),
              IconButton(icon: const Icon(Icons.share),             onPressed: () {}),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  dataAV.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error:   (_, __) => const SizedBox.shrink(),
                    data: (data) => Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatBlock(label: 'Distance',   value: '${data.distanceKm} km'),
                        _StatBlock(
                          label: 'Elevation',
                          value: '+${data.elevationGainM} m',
                          onTap: () => _showElevationModal(context, data),
                        ),
                        _StatBlock(label: 'Est. Time',  value: data.estimatedTimeLabel),
                        _StatBlock(label: 'Difficulty', value: route.difficulty),
                        _StatBlock(
                          label: 'Type',
                          value: route.shape.label,
                          icon: routeShapeIcon(route.shape),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 32),

                  Text(route.name, style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),

                  Row(children: [
                    ...List.generate(5, (i) {
                      if (i < route.rating.floor()) return const Icon(Icons.star,      color: Colors.amber, size: 20);
                      if (i < route.rating)         return const Icon(Icons.star_half, color: Colors.amber, size: 20);
                      return const Icon(Icons.star_border, color: Colors.amber, size: 20);
                    }),
                    const SizedBox(width: 8),
                    Text('${route.rating} · ${route.reviewCount} reviews'),
                  ]),

                  const SizedBox(height: 16),
                  Text('Description', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(route.description),

                  const SizedBox(height: 24),
                  Text('Waypoints', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final (icon, label) in [
                    (Icons.local_parking, 'Parking area'),
                    (Icons.water,         'Water source'),
                    (Icons.landscape,     'Summit viewpoint'),
                    (Icons.flag,          'Finish'),
                  ])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(icon, color: AppColors.forestGreen),
                      title: Text(label),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),

      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.download_outlined),
                label: const Text('Download'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => context.go('/tracking'),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Static map preview in the collapsible header ─────────────────────────────

class _RouteMapPreview extends StatelessWidget {
  const _RouteMapPreview({required this.points});
  final List<LatLng> points;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: _center(points),
        initialZoom: 13,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'app.sendero.sendero',
        ),
        PolylineLayer(polylines: [
          Polyline(points: points, color: AppColors.trailOrange, strokeWidth: 3),
        ]),
        MarkerLayer(markers: [
          _dot(points.first, Colors.green),
          _dot(points.last,  AppColors.trailOrange),
        ]),
      ],
    );
  }

  static Marker _dot(LatLng point, Color color) => Marker(
    point: point,
    width: 24,
    height: 24,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
      ),
    ),
  );
}

// ── Fullscreen map with playback controls ────────────────────────────────────

class _FullscreenRouteMap extends StatefulWidget {
  const _FullscreenRouteMap({required this.name, required this.points});
  final String name;
  final List<LatLng> points;

  @override
  State<_FullscreenRouteMap> createState() => _FullscreenRouteMapState();
}

class _FullscreenRouteMapState extends State<_FullscreenRouteMap> {
  final _mapController = MapController();

  int  _playIndex  = 0;
  bool _isPlaying  = false;
  Timer? _timer;

  // Advance ~1 point every 80 ms → full route in ~58 s for 729 pts
  static const _tickMs    = 80;
  static const _step      = 1;

  int get _last => widget.points.length - 1;
  double get _progress => _last == 0 ? 0 : _playIndex / _last;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _play() {
    if (_playIndex >= _last) _playIndex = 0; // restart if at end
    setState(() => _isPlaying = true);
    _timer = Timer.periodic(const Duration(milliseconds: _tickMs), (_) {
      if (!mounted) return;
      setState(() {
        _playIndex = (_playIndex + _step).clamp(0, _last);
        if (_playIndex >= _last) _pause();
      });
      _mapController.move(widget.points[_playIndex], _mapController.camera.zoom);
    });
  }

  void _pause() {
    _timer?.cancel();
    _timer = null;
    if (mounted) setState(() => _isPlaying = false);
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    setState(() {
      _isPlaying  = false;
      _playIndex  = 0;
    });
    _mapController.move(_center(widget.points), 13);
  }

  void _seekTo(double value) {
    _pause();
    setState(() => _playIndex = (value * _last).round().clamp(0, _last));
    _mapController.move(widget.points[_playIndex], _mapController.camera.zoom);
  }

  @override
  Widget build(BuildContext context) {
    final pts     = widget.points;
    final current = pts[_playIndex];
    final walked  = pts.sublist(0, _playIndex + 1);

    return Scaffold(
      body: Stack(
        children: [
          // ── Map ────────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: _center(pts), initialZoom: 13),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'app.sendero.sendero',
              ),
              // Full route in grey
              PolylineLayer(polylines: [
                Polyline(points: pts, color: Colors.grey.shade400, strokeWidth: 3),
              ]),
              // Walked portion in orange
              if (walked.length > 1)
                PolylineLayer(polylines: [
                  Polyline(points: walked, color: AppColors.trailOrange, strokeWidth: 4),
                ]),
              MarkerLayer(markers: [
                _RouteMapPreview._dot(pts.first, Colors.green),
                _RouteMapPreview._dot(pts.last,  Colors.grey),
                // Current position
                Marker(
                  point: current,
                  width: 20,
                  height: 20,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.trailOrange,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black45)],
                    ),
                  ),
                ),
              ]),
            ],
          ),

          // ── Back button ────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _MapBtn(icon: Icons.arrow_back, onTap: () => Navigator.pop(context)),
            ),
          ),

          // ── Zoom controls ──────────────────────────────────────────────────
          Positioned(
            right: 12,
            bottom: 160,
            child: Column(
              children: [
                _MapBtn(icon: Icons.add, onTap: () => _mapController.move(
                  _mapController.camera.center, _mapController.camera.zoom + 1)),
                const SizedBox(height: 8),
                _MapBtn(icon: Icons.remove, onTap: () => _mapController.move(
                  _mapController.camera.center, _mapController.camera.zoom - 1)),
                const SizedBox(height: 8),
                _MapBtn(icon: Icons.center_focus_strong,
                  onTap: () => _mapController.move(_center(pts), 13)),
              ],
            ),
          ),

          // ── Playback bar ───────────────────────────────────────────────────
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black26)],
              ),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Progress slider
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor:   AppColors.trailOrange,
                      inactiveTrackColor: Colors.grey.shade300,
                      thumbColor:         AppColors.trailOrange,
                      overlayColor:       AppColors.trailOrange.withOpacity(0.2),
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    ),
                    child: Slider(
                      value: _progress,
                      onChanged: _seekTo,
                    ),
                  ),

                  // Progress labels
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${(_progress * 100).toStringAsFixed(0)}%',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        Text(
                          widget.name,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Stop
                      IconButton(
                        icon: const Icon(Icons.stop_circle_outlined),
                        iconSize: 36,
                        color: Colors.grey.shade600,
                        onPressed: _stop,
                        tooltip: 'Stop',
                      ),
                      const SizedBox(width: 24),
                      // Play / Pause
                      SizedBox(
                        width: 64,
                        height: 64,
                        child: Material(
                          color: AppColors.trailOrange,
                          shape: const CircleBorder(),
                          elevation: 4,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _isPlaying ? _pause : _play,
                            child: Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                              size: 32,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      // Center on current position
                      IconButton(
                        icon: const Icon(Icons.my_location),
                        iconSize: 36,
                        color: Colors.grey.shade600,
                        onPressed: () => _mapController.move(current, _mapController.camera.zoom),
                        tooltip: 'Center on position',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable map button ───────────────────────────────────────────────────────

class _MapBtn extends StatelessWidget {
  const _MapBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(8),
    elevation: 2,
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(8), child: Icon(icon, size: 22)),
    ),
  );
}

// ── Elevation modal ───────────────────────────────────────────────────────────

void _showElevationModal(BuildContext context, RouteData data) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Elevation',
              style: Theme.of(dialogContext).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            _ElevationRow(icon: Icons.arrow_upward,  color: AppColors.forestGreen,
              label: 'Ascent',  value: '+${data.elevationGainM} m'),
            const SizedBox(height: 12),
            _ElevationRow(icon: Icons.arrow_downward, color: Colors.redAccent,
              label: 'Descent', value: '-${data.elevationLossM} m'),
            const Divider(height: 28),
            _ElevationRow(
              icon: Icons.swap_vert, color: Colors.grey,
              label: 'Net gain',
              value: '${data.elevationGainM - data.elevationLossM >= 0 ? '+' : ''}'
                     '${data.elevationGainM - data.elevationLossM} m',
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ElevationRow extends StatelessWidget {
  const _ElevationRow({required this.icon, required this.color,
      required this.label, required this.value});
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 18),
      ),
      const SizedBox(width: 12),
      Text(label, style: Theme.of(context).textTheme.bodyMedium),
      const Spacer(),
      Text(value, style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(color: color, fontWeight: FontWeight.bold)),
    ],
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

LatLng _center(List<LatLng> pts) {
  final lat = pts.map((p) => p.latitude).reduce((a, b) => a + b)  / pts.length;
  final lng = pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
  return LatLng(lat, lng);
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.label, required this.value, this.icon, this.onTap});
  final String label;
  final String value;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null)
          Icon(icon, size: 18, color: AppColors.forestGreen)
        else
          Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppColors.forestGreen, fontWeight: FontWeight.bold)),
        if (icon != null)
          Text(value, style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.forestGreen, fontWeight: FontWeight.bold)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            if (onTap != null) ...[
              const SizedBox(width: 2),
              Icon(Icons.info_outline, size: 11, color: Colors.grey.shade400),
            ],
          ],
        ),
      ],
    );
    if (onTap == null) return content;
    return GestureDetector(onTap: onTap, child: content);
  }
}
