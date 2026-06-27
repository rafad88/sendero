import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/map/presentation/map_screen.dart';
import '../../features/offline/presentation/offline_maps_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/routes/presentation/explore_screen.dart';
import '../../features/routes/presentation/route_detail_screen.dart';
import '../../features/tracking/presentation/save_activity_screen.dart';
import '../../features/tracking/presentation/tracking_screen.dart';
import '../widgets/main_shell.dart';

// Bridges Riverpod auth state into a ChangeNotifier that GoRouter can listen to.
// The router is created once; auth changes trigger a redirect re-evaluation
// without recreating the GoRouter widget tree.
class _AuthRouterNotifier extends ChangeNotifier {
  _AuthRouterNotifier(Ref ref) {
    ref.listen<AsyncValue<User?>>(authStateProvider, (_, __) {
      notifyListeners();
    });
  }
}

final _authRouterNotifierProvider = Provider<_AuthRouterNotifier>((ref) {
  return _AuthRouterNotifier(ref);
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(_authRouterNotifierProvider);

  return GoRouter(
    initialLocation: '/map',
    refreshListenable: notifier,
    redirect: (context, state) {
      final isLoggedIn =
          Supabase.instance.client.auth.currentSession?.user != null;
      final loc = state.matchedLocation;
      final isAuthRoute  = loc.startsWith('/auth');
      final isOnboarding = loc == '/onboarding';

      if (isLoggedIn && isAuthRoute) return '/map';

      if (!isLoggedIn && !isAuthRoute && !isOnboarding) {
        final guestAllowed = loc.startsWith('/map') ||
            loc.startsWith('/explore') ||
            loc.startsWith('/tracking');
        if (!guestAllowed) return '/onboarding';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/auth/login',
        builder: (_, __) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/map',
            pageBuilder: (_, __) => const NoTransitionPage(child: MapScreen()),
          ),
          GoRoute(
            path: '/explore',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: ExploreScreen()),
            routes: [
              GoRoute(
                path: 'route/:id',
                builder: (_, state) =>
                    RouteDetailScreen(routeId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: ProfileScreen()),
            routes: [
              GoRoute(
                path: 'offline-maps',
                builder: (_, __) => const OfflineMapsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/tracking',
        builder: (_, __) => const TrackingScreen(),
      ),
      GoRoute(
        path: '/tracking/save',
        builder: (_, state) =>
            SaveActivityScreen(trackId: state.extra as String),
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Route not found: ${state.error}')),
    ),
  );
});
