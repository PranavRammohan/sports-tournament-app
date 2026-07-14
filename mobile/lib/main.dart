import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/select_sports_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/browse_leagues_screen.dart';
import 'screens/pending_matches_screen.dart';

void main() {
  runApp(
    MaterialApp(
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/select-sports': (context) => const SelectSportsScreen(),
        '/home': (context) => const HomeScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/leagues': (context) => const BrowseLeaguesScreen(),
        '/pending-matches': (context) => const PendingMatchesScreen(),
      },
      debugShowCheckedModeBanner: false,
    ),
  );
}
