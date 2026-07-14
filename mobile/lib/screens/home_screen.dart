// home_screen.dart
import 'package:flutter/material.dart';
import '../main.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Login successful! 🎉'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sports League')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Welcome back 👋',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'What would you like to do?',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            _DashboardTile(
              icon: Icons.person_outline,
              iconColor: AppColors.primary,
              title: 'Profile',
              subtitle: 'View your info and ratings',
              onTap: () => Navigator.pushNamed(context, '/profile'),
            ),
            const SizedBox(height: 14),
            _DashboardTile(
              icon: Icons.groups_outlined,
              iconColor: AppColors.accent,
              title: 'My Leagues',
              subtitle: 'Leagues you\'ve joined',
              onTap: () => Navigator.pushNamed(context, '/my-leagues'),
            ),
            const SizedBox(height: 14),
            _DashboardTile(
              icon: Icons.explore_outlined,
              iconColor: AppColors.success,
              title: 'Browse Leagues',
              subtitle: 'Find and join new leagues',
              onTap: () => Navigator.pushNamed(context, '/leagues'),
            ),
            const SizedBox(height: 14),
            _DashboardTile(
              icon: Icons.pending_actions_outlined,
              iconColor: AppColors.danger,
              title: 'Pending Confirmations',
              subtitle: 'Matches waiting on you',
              onTap: () => Navigator.pushNamed(context, '/pending-matches'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DashboardTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
