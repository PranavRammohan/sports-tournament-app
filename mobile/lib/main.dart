import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/select_sports_screen.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding_screen.dart';

class AppColors {
  static const Color primary = Color(0xFF1E293B);
  static const Color primaryDark = Color(0xFF0F172A);
  static const Color accent = Color(0xFFB8860B);
  static const Color background = Color(0xFFF7F7F5);
  static const Color success = Color(0xFF2E9E5B);
  static const Color danger = Color(0xFFC0392B);
  static const Color warning = Color(0xFFB8860B);
  static const Color textDark = Color(0xFF1A1D29);
  static const Color textGrey = Color(0xFF6B7280);

  // Dark mode surface tones
  static const Color darkBackground = Color(0xFF121317);
  static const Color darkSurface = Color(0xFF1C1E24);
  static const Color darkTextGrey = Color(0xFF9CA3AF);
}

// Shared card shadow, so every custom Container-as-card across the app uses
// the same depth instead of each screen inventing its own. Use like:
//   decoration: BoxDecoration(
//     color: Theme.of(context).cardColor,
//     borderRadius: BorderRadius.circular(8),
//     boxShadow: AppShadows.card(isDark),
//   ),
class AppShadows {
  static List<BoxShadow> card(bool isDark) {
    return [
      BoxShadow(
        color: isDark
            ? Colors.black.withValues(alpha: 0.35)
            : Colors.black.withValues(alpha: 0.06),
        blurRadius: isDark ? 10 : 8,
        offset: const Offset(0, 2),
      ),
    ];
  }
}

// Global theme mode notifier — read at startup from SharedPreferences,
// updated instantly from Profile's dark mode toggle.
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
  ThemeMode.light,
);

Future<void> _loadSavedThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('darkMode') ?? false;
  themeModeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
}

Future<bool> _hasSeenOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('hasSeenOnboarding') ?? false;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _loadSavedThemeMode();
  final seenOnboarding = await _hasSeenOnboarding();
  runApp(RallyXApp(initialRoute: seenOnboarding ? '/login' : '/onboarding'));
}

class RallyXApp extends StatelessWidget {
  final String initialRoute;

  const RallyXApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          initialRoute: initialRoute,
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
          themeMode: mode,
          routes: {
            '/onboarding': (context) => const OnboardingScreen(),
            '/login': (context) => const LoginScreen(),
            '/signup': (context) => const SignupScreen(),
            '/select-sports': (context) => const SelectSportsScreen(),
            '/home': (context) => const MainShell(),
          },
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

ThemeData _buildLightTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        elevation: 0,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      margin: EdgeInsets.zero,
    ),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: AppColors.textDark,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.textDark,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textDark,
      ),
      bodyMedium: TextStyle(fontSize: 13, color: AppColors.textGrey),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.white,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
    ),
  );
}

ThemeData _buildDarkTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.darkBackground,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
      primary: AppColors.accent,
      secondary: AppColors.accent,
      surface: AppColors.darkSurface,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkSurface,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        elevation: 0,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accent,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade700),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade700),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    ),
    cardTheme: CardThemeData(
      color: AppColors.darkSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade800),
      ),
      margin: EdgeInsets.zero,
    ),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      bodyMedium: TextStyle(fontSize: 13, color: AppColors.darkTextGrey),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.white,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
    ),
  );
}
