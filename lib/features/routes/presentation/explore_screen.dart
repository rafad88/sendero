import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/route_provider.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _searchController = TextEditingController();
  String _selectedActivity = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<LocalRoute> get _filtered {
    final query = _searchController.text.toLowerCase();
    return localRoutes.where((r) {
      final matchesActivity = _selectedActivity == 'all' || r.activityType == _selectedActivity;
      final matchesQuery = query.isEmpty || r.name.toLowerCase().contains(query);
      return matchesActivity && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final routes = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: 'Search trails...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.white70),
          ),
          style: const TextStyle(color: Colors.white),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.tune), onPressed: _showFilters),
        ],
      ),
      body: Column(
        children: [
          // Activity filter chips
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final (type, label) in [
                  ('all',  'All'),
                  ('hike', 'Hike'),
                  ('bike', 'Bike'),
                  ('run',  'Run'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(label),
                      selected: _selectedActivity == type,
                      onSelected: (_) => setState(() => _selectedActivity = type),
                      selectedColor: AppColors.forestGreen.withOpacity(0.2),
                    ),
                  ),
              ],
            ),
          ),

          if (routes.isEmpty)
            const Expanded(
              child: Center(child: Text('No routes found.', style: TextStyle(color: Colors.grey))),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: routes.length,
                itemBuilder: (_, i) => _RouteCard(
                  route: routes[i],
                  onTap: () => context.go('/explore/route/${routes[i].id}'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showFilters() {
    showModalBottomSheet(
      context: context,
      builder: (_) => const _FiltersSheet(),
    );
  }
}

class _RouteCard extends ConsumerWidget {
  const _RouteCard({required this.route, required this.onTap});
  final LocalRoute route;
  final VoidCallback onTap;

  static const _difficultyColors = {
    'Easy':     Colors.green,
    'Moderate': Colors.orange,
    'Hard':     Colors.deepOrange,
    'Expert':   Colors.red,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color   = _difficultyColors[route.difficulty] ?? Colors.grey;
    final dataAV  = ref.watch(routeDataProvider(route.id));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(route.name, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Row(children: [
                    const Icon(Icons.star, size: 16, color: Colors.amber),
                    const SizedBox(width: 2),
                    Text(route.rating.toStringAsFixed(1)),
                  ]),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(route.difficulty, style: TextStyle(color: color, fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  dataAV.when(
                    loading: () => const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (data) => Row(
                      children: [
                        const Icon(Icons.straighten, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text('${data.distanceKm} km', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                        const SizedBox(width: 12),
                        const Icon(Icons.terrain, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text('+${data.elevationGainM} m', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FiltersSheet extends StatelessWidget {
  const _FiltersSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Filters', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Text('Distance', style: Theme.of(context).textTheme.labelLarge),
          RangeSlider(values: const RangeValues(0, 50), max: 100, onChanged: null),
          Text('Difficulty', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Apply')),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
