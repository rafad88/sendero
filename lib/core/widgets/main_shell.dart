import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainShell extends StatelessWidget {
  const MainShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indexFromLocation(GoRouterState.of(context).matchedLocation),
        onDestinationSelected: (i) => _onTap(context, i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined),     selectedIcon: Icon(Icons.map),     label: 'Map'),
          NavigationDestination(icon: Icon(Icons.explore_outlined),  selectedIcon: Icon(Icons.explore),  label: 'Explore'),
          NavigationDestination(icon: Icon(Icons.person_outlined),   selectedIcon: Icon(Icons.person),   label: 'Profile'),
        ],
      ),
    );
  }

  int _indexFromLocation(String location) {
    if (location.startsWith('/explore')) return 1;
    if (location.startsWith('/profile')) return 2;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0: context.go('/map');
      case 1: context.go('/explore');
      case 2: context.go('/profile');
    }
  }
}
