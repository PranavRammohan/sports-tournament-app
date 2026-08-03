// profile_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../api_client.dart';
import '../widgets/sport_icon.dart';
import '../widgets/player_avatar.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/win_rate_bar.dart';
import '../widgets/rating_sparkline.dart';
import '../utils.dart';
import '../constants/sports.dart';
import 'add_sport_screen.dart';
import 'edit_profile_screen.dart';
import 'onboarding_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _user;
  List<dynamic> _sports = [];
  bool _loading = true;
  bool _isDarkMode = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _isDarkMode = themeModeNotifier.value == ThemeMode.dark;
    _loadProfile();
  }

  void refresh() {
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final userJson = prefs.getString('user');

      if (token == null || userJson == null) {
        setState(() => _error = 'Not logged in.');
        return;
      }

      setState(() => _user = jsonDecode(userJson));

      final res = await ApiClient.get('/sports/mine');

      if (res.statusCode != 200) {
        setState(() => _error = res.errorOr('Could not load sports.'));
        return;
      }

      setState(() => _sports = res.data['sports']);
    } catch (err) {
      setState(
        () => _error = 'Could not reach the server. Check your connection.',
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleDarkMode(bool value) async {
    HapticFeedback.selectionClick();
    setState(() => _isDarkMode = value);
    themeModeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', value);
  }

  Future<void> _handleDeleteAccount() async {
    final passwordController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('Delete account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently removes your personal details. Your match '
              'history stays visible to opponents, but your name is replaced '
              'with "Deleted user" and you can never log in again.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Enter your password to confirm',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete Account',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final res = await ApiClient.delete(
      '/auth/account',
      body: {'password': passwordController.text},
    );

    if (res.statusCode != 200) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.errorOr('Could not delete your account.'))),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('authToken');
    await prefs.remove('user');
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('Log out?'),
        content: const Text("You'll need to sign in again to use RallyX."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Log Out',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    HapticFeedback.mediumImpact();
    final prefs = await SharedPreferences.getInstance();
    // Clear only the session, not app-level preferences like darkMode/
    // hasSeenOnboarding — those should survive a logout.
    await prefs.remove('authToken');
    await prefs.remove('user');
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  String _formatSportName(String sport) {
    return sport
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  Map<String, Map<String, dynamic>> _groupSportsByName() {
    final Map<String, Map<String, dynamic>> grouped = {};
    for (final row in _sports) {
      final sport = row['sport'];
      grouped.putIfAbsent(sport, () => {});
      grouped[sport]![row['format']] = row;
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final groupedSports = _groupSportsByName();
    final existingSportKeys = groupedSports.keys.toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final borderColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    final subtleTextColor = isDark
        ? Colors.grey.shade400
        : Colors.grey.shade600;
    final primaryTextColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark;
    final ratingRowBg = isDark
        ? AppColors.darkBackground
        : AppColors.background;

    final profilePicUrl = _user?['profilePicUrl'];
    final hasProfilePic = profilePicUrl != null && profilePicUrl.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
            tooltip: 'Log out',
          ),
        ],
      ),
      body: _loading
          ? const SkeletonList()
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _loadProfile,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadProfile,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: AppShadows.card(isDark),
                    ),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: InkWell(
                            onTap: () async {
                              HapticFeedback.selectionClick();
                              final updated = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      EditProfileScreen(currentUser: _user!),
                                ),
                              );
                              if (updated == true) _loadProfile();
                            },
                            child: const Padding(
                              padding: EdgeInsets.only(bottom: 4),
                              child: Icon(
                                Icons.edit,
                                size: 18,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ),
                        PlayerAvatar(
                          username: _user?['username'] ?? '?',
                          profilePicUrl: hasProfilePic ? profilePicUrl : null,
                          radius: 30,
                          backgroundColor: Colors.white,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _user?['username'] ?? '',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _InfoChip(
                              icon: Icons.location_on,
                              label: _user?['location'] ?? '',
                            ),
                            _InfoChip(
                              icon: Icons.phone,
                              label: _user?['phoneNumber'] ?? '',
                            ),
                            if ((_user?['email'] ?? '').isNotEmpty)
                              _InfoChip(
                                icon: Icons.email,
                                label: _user?['email'] ?? '',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderColor),
                      boxShadow: AppShadows.card(isDark),
                    ),
                    child: SwitchListTile(
                      value: _isDarkMode,
                      onChanged: _toggleDarkMode,
                      title: Text(
                        'Dark Mode',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: primaryTextColor,
                        ),
                      ),
                      secondary: Icon(
                        Icons.dark_mode_outlined,
                        color: primaryTextColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderColor),
                      boxShadow: AppShadows.card(isDark),
                    ),
                    child: ListTile(
                      leading: Icon(
                        Icons.help_outline,
                        color: primaryTextColor,
                      ),
                      title: Text(
                        'How RallyX works',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: primaryTextColor,
                        ),
                      ),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const OnboardingScreen(replay: true),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Your Sports',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          IconButton(
                            icon: const Icon(Icons.info_outline, size: 18),
                            tooltip: 'About ratings',
                            onPressed: _showRatingInfoDialog,
                          ),
                        ],
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          HapticFeedback.selectionClick();
                          final added = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AddSportScreen(
                                existingSports: existingSportKeys,
                              ),
                            ),
                          );
                          if (added == true) _loadProfile();
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Sport'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (groupedSports.isEmpty)
                    Text(
                      'No sports selected yet.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
                  else
                    ...groupedSports.entries.map((entry) {
                      final sport = entry.key;
                      final formats = entry.value;
                      final isTableTennis = sport == 'table_tennis';
                      final singles = formats['singles'];
                      final doubles = formats['doubles'];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  sportIcon(sport, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    _formatSportName(sport),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              if (isTableTennis && singles != null)
                                _ratingRow(
                                  'Rating',
                                  singles,
                                  ratingRowBg,
                                  primaryTextColor,
                                  subtleTextColor,
                                )
                              else ...[
                                if (singles != null)
                                  _ratingRow(
                                    'Singles',
                                    singles,
                                    ratingRowBg,
                                    primaryTextColor,
                                    subtleTextColor,
                                  ),
                                if (singles != null && doubles != null)
                                  const SizedBox(height: 8),
                                if (doubles != null)
                                  _ratingRow(
                                    'Doubles',
                                    doubles,
                                    ratingRowBg,
                                    primaryTextColor,
                                    subtleTextColor,
                                  ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 22),
                  Container(
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.delete_outline,
                        color: AppColors.danger,
                      ),
                      title: const Text(
                        'Delete Account',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.danger,
                        ),
                      ),
                      onTap: _handleDeleteAccount,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _ratingRow(
    String label,
    Map<String, dynamic> data,
    Color bgColor,
    Color textColor,
    Color subtleTextColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: textColor,
                ),
              ),
              Text(
                '${data['matches_played']} matches · ${data['wins']}W ${data['losses']}L',
                style: TextStyle(fontSize: 11, color: subtleTextColor),
              ),
              if ((data['matches_played'] ?? 0) > 0) ...[
                const SizedBox(height: 4),
                SizedBox(
                  width: 90,
                  child: WinRateBar(
                    wins: data['wins'] ?? 0,
                    losses: data['losses'] ?? 0,
                  ),
                ),
              ],
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_user?['id'] != null &&
                  data['matches_played'] != null &&
                  data['matches_played'] > 0) ...[
                RatingSparkline(
                  userId: _user!['id'] as int,
                  sport: data['sport'],
                  format: data['format'],
                ),
                const SizedBox(width: 10),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatRating(data['sport'], data['rating']),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.accent,
                    ),
                  ),
                  if (ratingBandFor(data['sport'], data['rating']) != null)
                    Text(
                      ratingBandFor(data['sport'], data['rating'])!,
                      style: TextStyle(fontSize: 10, color: subtleTextColor),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showRatingInfoDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('About ratings'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your rating moves after every confirmed match — up when you '
                'win, down when you lose, more for a surprising result and '
                'less for an expected one.',
              ),
              SizedBox(height: 12),
              Text(
                'Each sport uses its own practical scale, so the numbers '
                "aren't comparable across sports:",
              ),
              SizedBox(height: 8),
              Text('• Badminton: roughly 6000–8500'),
              Text('• Tennis: roughly 2.5–13'),
              Text('• Table Tennis: roughly 1000–2500'),
              Text('• Pickleball: roughly 2.5–7'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
