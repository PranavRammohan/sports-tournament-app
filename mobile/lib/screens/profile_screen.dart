// profile_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

const String apiUrl = 'http://localhost:3000/api';

const Map<String, String> sportEmojis = {
  'badminton': '🏸',
  'tennis': '🎾',
  'table_tennis': '🏓',
  'pickleball': '🥒',
};

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _user;
  List<dynamic> _sports = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
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
        Uri.parse('$apiUrl/sports/mine'),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.pushNamed(context, '/match-history'),
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
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: Colors.white,
                          child: Text(
                            (_user?['username'] ?? '?')[0].toUpperCase(),
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _user?['username'] ?? '',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
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
                  const SizedBox(height: 28),
                  Text(
                    'Your Sports',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 14),
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
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: Text(
                                        sportEmojis[sport] ?? '🏅',
                                        style: const TextStyle(fontSize: 18),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    _formatSportName(sport),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (isTableTennis && singles != null)
                                _ratingRow('Rating', singles)
                              else ...[
                                if (singles != null)
                                  _ratingRow('Singles', singles),
                                if (singles != null && doubles != null)
                                  const SizedBox(height: 10),
                                if (doubles != null)
                                  _ratingRow('Doubles', doubles),
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

  Widget _ratingRow(String label, Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              Text(
                '${data['matches_played']} matches · ${data['wins']}W ${data['losses']}L',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          Text(
            '${data['rating']}',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
