import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/route_provider.dart';

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
                    : _RouteMapPreview(
                        points: data.points,
                        onExpand: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _FullscreenRouteMap(
                              name: route.name,
                              points: data.points,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            actions: [
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
                        _StatBlock(label: 'Elevation',  value: '+${data.elevationGainM} m'),
                        _StatBlock(label: 'Est. Time',  value: data.estimatedTimeLabel),
                        _StatBlock(label: 'Difficulty', value: route.difficulty),
                      ],
                    ),
                  ),

                  const Divider(height: 32),

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

// ── Map preview inside the collapsible header ────────────────────────────────

class _RouteMapPreview extends StatelessWidget {
  const _RouteMapPreview({required this.points, required this.onExpand});
  final List<LatLng> points;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: _center(points),
            initialZoom: 13,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'app.sendero.sendero',
            ),
            PolylineLayer(polylines: [
              Polyline(
                points: points,
                color: AppColors.trailOrange,
                strokeWidth: 3,
              ),
            ]),
            MarkerLayer(markers: [
              _dot(points.first, Colors.green),
              _dot(points.last,  AppColors.trailOrange),
            ]),
          ],
        ),

        Positioned(
          right: 8,
          bottom: 8,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onExpand,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.fullscreen, size: 22),
              ),
            ),
          ),
        ),
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

// ── Fullscreen interactive map ───────────────────────────────────────────────

class _FullscreenRouteMap extends StatefulWidget {
  const _FullscreenRouteMap({required this.name, required this.points});
  final String name;
  final List<LatLng> points;

  @override
  State<_FullscreenRouteMap> createState() => _FullscreenRouteMapState();
}

class _FullscreenRouteMapState extends State<_FullscreenRouteMap> {
  final _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center(widget.points),
              initialZoom: 13,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'app.sendero.sendero',
              ),
              PolylineLayer(polylines: [
                Polyline(
                  points: widget.points,
                  color: AppColors.trailOrange,
                  strokeWidth: 4,
                ),
              ]),
              MarkerLayer(markers: [
                _RouteMapPreview._dot(widget.points.first, Colors.green),
                _RouteMapPreview._dot(widget.points.last,  AppColors.trailOrange),
              ]),
            ],
          ),

          // Back button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                elevation: 2,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.pop(context),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.arrow_back),
                  ),
                ),
              ),
            ),
          ),

          // Zoom controls
          Positioned(
            right: 12,
            bottom: 48,
            child: Column(
              children: [
                _MapBtn(
                  icon: Icons.add,
                  onTap: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  ),
                ),
                const SizedBox(height: 8),
                _MapBtn(
                  icon: Icons.remove,
                  onTap: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  ),
                ),
                const SizedBox(height: 8),
                _MapBtn(
                  icon: Icons.center_focus_strong,
                  onTap: () => _mapController.move(_center(widget.points), 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 22),
      ),
    ),
  );
}

// ── Helpers ──────────────────────────────────────────────────────────────────

LatLng _center(List<LatLng> pts) {
  final lat = pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
  final lng = pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
  return LatLng(lat, lng);
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: AppColors.forestGreen, fontWeight: FontWeight.bold,
      )),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}
