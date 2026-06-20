import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';

class OfflineMapsScreen extends ConsumerWidget {
  const OfflineMapsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offline Maps')),
      body: Column(
        children: [
          // Storage summary
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.forestGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.storage, color: AppColors.forestGreen),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Storage used', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: 0.08, minHeight: 6),
                      ),
                      const SizedBox(height: 4),
                      const Text('45 MB of 3 GB used', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Downloaded regions list
          Expanded(
            child: ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('DOWNLOADED REGIONS', style: TextStyle(fontSize: 11, color: Colors.grey, letterSpacing: 1)),
                ),

                // Placeholder items — will be replaced by Riverpod provider
                _RegionTile(
                  name: 'Pyrenees Central',
                  sizeLabel: '45 MB',
                  dateLabel: 'Downloaded Jun 20',
                  onDelete: () => _confirmDelete(context, 'Pyrenees Central'),
                  onUpdate: () {},
                ),
                _RegionTile(
                  name: 'Madrid Province',
                  sizeLabel: '32 MB',
                  dateLabel: 'Downloaded Jun 18',
                  onDelete: () => _confirmDelete(context, 'Madrid Province'),
                  onUpdate: () {},
                ),

                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Tip: Long-press any map area to download it for offline use.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pop(context), // go back to map to select area
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Download new area'),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, String name) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text('This area will no longer be available offline.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    // TODO: trigger deletion via provider
  }
}

class _RegionTile extends StatelessWidget {
  const _RegionTile({
    required this.name,
    required this.sizeLabel,
    required this.dateLabel,
    required this.onDelete,
    required this.onUpdate,
  });

  final String name;
  final String sizeLabel;
  final String dateLabel;
  final VoidCallback onDelete;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.map, color: AppColors.forestGreen),
        title: Text(name),
        subtitle: Text('$sizeLabel · $dateLabel', style: const TextStyle(fontSize: 12)),
        trailing: PopupMenuButton(
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'update', child: Text('Update')),
            const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
          ],
          onSelected: (v) => v == 'delete' ? onDelete() : onUpdate(),
        ),
      ),
    );
  }
}
