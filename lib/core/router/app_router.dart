import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/map/presentation/map_screen.dart';
import '../../features/tracking/presentation/tracking_screen.dart';
import '../../features/tracking/presentation/save_activity_screen.dart';
import '../../features/routes/presentation/route_detail_screen.dart';
import '../../features/routes/presentation/explore_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/offline/presentation/offline_maps_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../widgets/main_shell.dart';

part 'app_router.g.dart';

@riverpod
GoRouter appRouter(AppRouterRef ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/map',
    redirect: (context, state) {
      final isLoggedIn   = authState.valueOrNull != null;
      final isAuthRoute  = state.matchedLocation.startsWith('/auth');
      final isOnboarding = state.matchedLocation == '/onboarding';

      // Auth route while logged in → go to map
      if (isLoggedIn && isAuthRoute) return '/map';
      // Not logged in and trying to access auth-only routes → onboarding
      // Map, explore, tracking are accessible as guest
      if (!isLoggedIn && !isAuthRoute && !isOnboarding) {
        final guestAllowed = state.matchedLocation.startsWith('/map') ||
            state.matchedLocation.startsWith('/explore') ||
            state.matchedLocation.startsWith('/tracking');
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
            pageBuilder: (_, __) => const NoTransitionPage(child: ExploreScreen()),
            routes: [
              GoRoute(
                path: 'route/:id',
                builder: (_, state) => RouteDetailScreen(routeId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (_, __) => const NoTransitionPage(child: ProfileScreen()),
            routes: [
              GoRoute(
                path: 'offline-maps',
                builder: (_, __) => const OfflineMapsScreen(),
              ),
            ],
          ),
        ],
      ),
      // Full-screen routes (outside shell — no bottom nav)
      GoRoute(
        path: '/tracking',
        builder: (_, __) => const TrackingScreen(),
      ),
      GoRoute(
        path: '/tracking/save',
        builder: (_, state) => SaveActivityScreen(
          trackId: state.extra as String,
        ),
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Route not found: ${state.error}')),
    ),
  );
}
