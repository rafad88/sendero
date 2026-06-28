import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.go('/profile/offline-maps'),
          ),
        ],
      ),
      body: ListView(
        children: [
          // Avatar + stats
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _Avatar(url: user.userMetadata?['avatar_url'] as String?),
                const SizedBox(height: 12),
                Text(
                  (user.userMetadata?['full_name'] as String?) ??
                      (user.userMetadata?['name'] as String?) ??
                      user.email ?? '',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: const [
                    _StatCell(label: 'Activities', value: '0'),
                    _StatCell(label: 'Distance',   value: '0 km'),
                    _StatCell(label: 'Elevation',  value: '0 m'),
                  ],
                ),
              ],
            ),
          ),

          const Divider(),

          // Menu items
          ListTile(
            leading: const Icon(Icons.map_outlined),
            title: const Text('Offline Maps'),
            subtitle: const Text('Manage downloaded regions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/profile/offline-maps'),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Activity History'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.bookmark_outline),
            title: const Text('Saved Routes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.route),
            title: const Text('My Routes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          ListTile(
            leading: Icon(Icons.add_location_alt_outlined, color: AppColors.forestGreen),
            title: const Text('Crear ruta'),
            subtitle: const Text('Importa un archivo GPX'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/profile/create-route'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
            onTap: () => ref.read(authNotifierProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.forestGreen)),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return CircleAvatar(
        radius: 40,
        backgroundImage: NetworkImage(url!),
        onBackgroundImageError: (_, __) {},
      );
    }
    return const CircleAvatar(
      radius: 40,
      child: Icon(Icons.person, size: 40),
    );
  }
}

