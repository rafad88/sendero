import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

class RouteDetailScreen extends ConsumerWidget {
  const RouteDetailScreen({required this.routeId, super.key});
  final String routeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Collapsed app bar with map preview thumbnail
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text('Route Name'),
              background: Container(color: AppColors.forestGreen.withOpacity(0.3)),
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
                  // Stats row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: const [
                      _StatBlock(label: 'Distance',  value: '12.4 km'),
                      _StatBlock(label: 'Elevation', value: '+640 m'),
                      _StatBlock(label: 'Est. Time', value: '3h 20m'),
                      _StatBlock(label: 'Difficulty',value: 'Moderate'),
                    ],
                  ),

                  const Divider(height: 32),

                  // Rating
                  Row(children: [
                    ...List.generate(5, (i) => Icon(
                      i < 4 ? Icons.star : Icons.star_half,
                      color: Colors.amber, size: 20,
                    )),
                    const SizedBox(width: 8),
                    const Text('4.3 · 156 reviews'),
                  ]),

                  const SizedBox(height: 16),
                  Text('Description', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                    'A beautiful circular route through the mountains with stunning views. '
                    'The path is well-marked and suitable for intermediate hikers.',
                  ),

                  const SizedBox(height: 24),
                  Text('Waypoints', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final (icon, label) in [
                    (Icons.local_parking, 'Parking area'),
                    (Icons.water, 'Water source'),
                    (Icons.landscape, 'Summit viewpoint'),
                    (Icons.flag, 'Finish'),
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
