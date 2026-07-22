// profile_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../config.dart';
import '../widgets/sport_icon.dart';
import 'match_history_screen.dart';
import 'add_sport_screen.dart';
import 'edit_profile_screen.dart';
import 'change_password_screen.dart';

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

  // Called by MainShell whenever this tab is tapped, so the profile
  // reflects any changes made elsewhere without needing a full reload.
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

      final response = await http.get(
        Uri.parse('$baseApiUrl/sports/mine'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);

      if (response.statusCode != 200) {
        setState(() => _error = data['error'] ?? 'Could not load sports.');
        return;
      }

      setState(() => _sports = data['sports']);
    } catch (err) {
      setState(
        () => _error = 'Could not reach the server. Check your connection.',
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleDarkMode(bool value) async {
    setState(() => _isDarkMode = value);
    themeModeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', value);
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.password),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
            ),
            tooltip: 'Change password',
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MatchHistoryScreen()),
            ),
            tooltip: 'Match history',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
            tooltip: 'Log out',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
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
                    ),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: InkWell(
                            onTap: () async {
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
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.white,
                          child: Text(
                            (_user?['username'] ?? '?')[0].toUpperCase(),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _InfoChip(
                              icon: Icons.location_on,
                              label: _user?['location'] ?? '',
                            ),
                            const SizedBox(width: 8),
                            _InfoChip(
                              icon: Icons.phone,
                              label: _user?['phoneNumber'] ?? '',
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
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Your Sports',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      TextButton.icon(
                        onPressed: () async {
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
            ],
          ),
          Text(
            '${data['rating']}',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppColors.accent,
            ),
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
