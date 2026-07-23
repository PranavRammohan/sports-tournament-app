// main_shell.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../config.dart';
import 'home_screen.dart';
import 'my_leagues_screen.dart';
import 'pending_matches_screen.dart';
import 'profile_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  int _pendingCount = 0;

  final _homeKey = GlobalKey<State<HomeScreen>>();
  final _leaguesKey = GlobalKey<State<MyLeaguesScreen>>();
  final _pendingKey = GlobalKey<State<PendingMatchesScreen>>();
  final _profileKey = GlobalKey<State<ProfileScreen>>();

  late final _screens = [
    HomeScreen(key: _homeKey),
    MyLeaguesScreen(key: _leaguesKey),
    PendingMatchesScreen(key: _pendingKey),
    ProfileScreen(key: _profileKey),
  ];

  @override
  void initState() {
    super.initState();
    _loadPendingCount();
  }

  Future<void> _loadPendingCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.get(
        Uri.parse('$baseApiUrl/matches/pending'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && mounted) {
        setState(() => _pendingCount = (data['matches'] as List).length);
      }
    } catch (err) {
      // fail silently
    }
  }

  void _refreshScreen(int i) {
    switch (i) {
      case 0:
        (_homeKey.currentState as dynamic)?.refresh();
        break;
      case 1:
        (_leaguesKey.currentState as dynamic)?.refresh();
        break;
      case 2:
        (_pendingKey.currentState as dynamic)?.refresh();
        break;
      case 3:
        (_profileKey.currentState as dynamic)?.refresh();
        break;
    }
  }

  void _onDestinationSelected(int i) {
    setState(() => _index = i);
    _refreshScreen(i);
    if (i == 2) {
      Future.delayed(const Duration(milliseconds: 400), _loadPendingCount);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navBarColor = Theme.of(context).cardColor;
    final unselectedColor = isDark
        ? Colors.grey.shade500
        : Colors.grey.shade600;

    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected ? AppColors.accent : unselectedColor,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: selected ? AppColors.accent : unselectedColor,
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _onDestinationSelected,
          backgroundColor: navBarColor,
          indicatorColor: AppColors.accent.withValues(alpha: 0.15),
          height: 60,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            const NavigationDestination(
              icon: Icon(Icons.list_alt_outlined),
              selectedIcon: Icon(Icons.list_alt),
              label: 'Tournaments',
            ),
            NavigationDestination(
              icon: _pendingCount > 0
                  ? Badge(
                      label: Text('$_pendingCount'),
                      backgroundColor: AppColors.danger,
                      child: const Icon(Icons.pending_actions_outlined),
                    )
                  : const Icon(Icons.pending_actions_outlined),
              selectedIcon: _pendingCount > 0
                  ? Badge(
                      label: Text('$_pendingCount'),
                      backgroundColor: AppColors.danger,
                      child: const Icon(Icons.pending_actions),
                    )
                  : const Icon(Icons.pending_actions),
              label: 'Pending',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
