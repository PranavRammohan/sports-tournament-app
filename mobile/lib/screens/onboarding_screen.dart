// onboarding_screen.dart
// Shown once, on first launch only, before the login screen. Explains the
// app's less-obvious mechanics (ratings, tournament formats, confirmation
// flow) so new users aren't confused by them the first time they show up.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

class _OnboardingSlide {
  final IconData icon;
  final String title;
  final String description;

  const _OnboardingSlide({
    required this.icon,
    required this.title,
    required this.description,
  });
}

const List<_OnboardingSlide> _slides = [
  _OnboardingSlide(
    icon: Icons.emoji_events_outlined,
    title: 'Join or host tournaments',
    description:
        'Round robins, knockouts, fixed-match leagues, or fully custom formats — join one, or set your own rules as host.',
  ),
  _OnboardingSlide(
    icon: Icons.trending_up,
    title: 'Ratings update after every match',
    description:
        'Every confirmed result adjusts your skill rating for that sport. Beat someone rated higher than you for a bigger boost.',
  ),
  _OnboardingSlide(
    icon: Icons.how_to_reg_outlined,
    title: 'Scores need confirmation',
    description:
        "When you report a match, your opponent confirms it before it counts — unless the host enters scores directly for that tournament.",
  ),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  void _next() {
    if (_page == _slides.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLast = _page == _slides.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: TextButton(
                  onPressed: _finish,
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(
                              alpha: isDark ? 0.2 : 0.08,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            slide.icon,
                            size: 56,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          slide.description,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontSize: 14, height: 1.4),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (index) {
                final active = index == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.accent
                        : AppColors.accent.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _next,
                  child: Text(isLast ? 'Get Started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
