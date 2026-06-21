import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/offline_provider.dart';

class OfflineMapsScreen extends ConsumerWidget {
  const OfflineMapsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packagesAV = ref.watch(offlinePackagesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mapas offline')),
      body: packagesAV.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text('Error: $e')),
        data: (packages) {
          final ready = packages.where((p) => p.status == 'ready').toList();
          final totalBytes = ready.fold<int>(0, (sum, p) => sum + p.sizeBytes);

          return Column(
            children: [
              // Storage summary
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.forestGreen.withValues(alpha: 0.1),
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
                          const Text('Espacio usado', style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(
                            _formatBytes(totalBytes),
                            style: const TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${ready.length} ruta${ready.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.forestGreen),
                    ),
                  ],
                ),
              ),

              if (ready.isEmpty)
                const Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.download_for_offline_outlined, size: 64, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('No hay rutas descargadas',
                            style: TextStyle(color: Colors.grey, fontSize: 16)),
                        SizedBox(height: 6),
                        Text('Abre una ruta y pulsa "Offline" para descargarla.',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                            textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: ready.length,
                    itemBuilder: (_, i) {
                      final pkg = ready[i];
                      final date = pkg.downloadedAt != null
                          ? DateTime.fromMillisecondsSinceEpoch(pkg.downloadedAt!)
                          : null;
                      return _PackageTile(
                        pkg: pkg,
                        dateLabel: date != null
                            ? 'Descargado ${date.day}/${date.month}/${date.year}'
                            : '',
                        onDelete: () => _confirmDelete(context, ref, pkg.id, pkg.name),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String id,
    String name,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('¿Borrar "$name"?'),
        content: const Text('Esta ruta dejará de estar disponible sin conexión.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(offlineNotifierProvider.notifier).deleteRoute(id);
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes == 0) return '0 MB';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _PackageTile extends StatelessWidget {
  const _PackageTile({
    required this.pkg,
    required this.dateLabel,
    required this.onDelete,
  });

  final OfflinePackagesTableData pkg;
  final String dateLabel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final size = pkg.sizeBytes < 1024 * 1024
        ? '${(pkg.sizeBytes / 1024).toStringAsFixed(1)} KB'
        : '${(pkg.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: AppColors.forestGreen,
          foregroundColor: Colors.white,
          child: Icon(Icons.map),
        ),
        title: Text(pkg.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('$size · $dateLabel',
            style: const TextStyle(fontSize: 12)),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: onDelete,
          tooltip: 'Borrar',
        ),
      ),
    );
  }
}
