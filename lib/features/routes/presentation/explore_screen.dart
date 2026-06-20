import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

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

  @override
  Widget build(BuildContext context) {
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
                for (final (type, label) in [('all','All'), ('hike','Hike'), ('bike','Bike'), ('run','Run')])
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

          // Route list (placeholder — will be replaced with Riverpod data)
          Expanded(
            child: ListView.builder(
              itemCount: 10,
              itemBuilder: (_, i) => _RouteCard(
                title: 'Sample Route ${i + 1}',
                distance: '${(i + 1) * 2.3} km',
                elevation: '+${(i + 1) * 120} m',
                difficulty: ((i % 5) + 1),
                rating: 4.2,
                onTap: () => context.go('/explore/route/sample-$i'),
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

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.title,
    required this.distance,
    required this.elevation,
    required this.difficulty,
    required this.rating,
    required this.onTap,
  });

  final String title;
  final String distance;
  final String elevation;
  final int    difficulty;
  final double rating;
  final VoidCallback onTap;

  static const _difficultyColors = [
    Colors.green,
    Colors.lightGreen,
    Colors.orange,
    Colors.deepOrange,
    Colors.red,
  ];
  static const _difficultyLabels = ['Easy', 'Easy+', 'Moderate', 'Hard', 'Expert'];

  @override
  Widget build(BuildContext context) {
    final color = _difficultyColors[(difficulty - 1).clamp(0, 4)];
    final label = _difficultyLabels[(difficulty - 1).clamp(0, 4)];

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
                    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Row(children: [
                    const Icon(Icons.star, size: 16, color: Colors.amber),
                    const SizedBox(width: 2),
                    Text(rating.toStringAsFixed(1)),
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
                    child: Text(label, style: TextStyle(color: color, fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.straighten, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(distance, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(width: 12),
                  const Icon(Icons.terrain, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(elevation, style: const TextStyle(fontSize: 13, color: Colors.grey)),
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
