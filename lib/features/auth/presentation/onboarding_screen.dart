import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  static const _pages = [
    _OnboardingPage(
      icon: Icons.wifi_off,
      title: 'Track anywhere.',
      subtitle: 'Even offline.',
      body: 'Record your hikes, rides, and runs with full GPS accuracy — no signal required.',
    ),
    _OnboardingPage(
      icon: Icons.download_for_offline_outlined,
      title: 'Download maps\nbefore you go.',
      subtitle: '',
      body: 'Save any area to your device. Navigate trails without spending a single MB of data.',
    ),
    _OnboardingPage(
      icon: Icons.volunteer_activism_outlined,
      title: 'Free.',
      subtitle: 'Always.',
      body: 'Offline maps, unlimited tracking, and route discovery — free forever. No tricks.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.forestGreen,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: _pages.length,
                itemBuilder: (_, i) => _pages[i],
              ),
            ),

            // Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width:  _currentPage == i ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _currentPage == i ? Colors.white : Colors.white38,
                  borderRadius: BorderRadius.circular(4),
                ),
              )),
            ),

            const SizedBox(height: 32),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _currentPage < _pages.length - 1
                  ? Row(
                      children: [
                        TextButton(
                          onPressed: () => context.go('/map'),
                          child: const Text('Skip', style: TextStyle(color: Colors.white70)),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () => _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          ),
                          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.forestGreen),
                          child: const Text('Next'),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        FilledButton(
                          onPressed: () => context.go('/map'),
                          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.forestGreen),
                          child: const Text('Get Started'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => context.go('/auth/login'),
                          child: const Text('I already have an account', style: TextStyle(color: Colors.white70)),
                        ),
                      ],
                    ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.white),
          const SizedBox(height: 32),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, height: 1.2),
          ),
          if (subtitle.isNotEmpty) ...[
            Text(
              subtitle,
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.5), height: 1.2),
            ),
          ],
          const SizedBox(height: 20),
          Text(body, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.85), height: 1.5)),
        ],
      ),
    );
  }
}
