// profile_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String apiUrl = 'http://localhost:3000/api';

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

  // Groups the flat list of {sport, format, rating, ...} rows into
  // one entry per sport, each holding its singles and doubles data together.
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
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.blue.shade100,
                    child: Text(
                      (_user?['username'] ?? '?')[0].toUpperCase(),
                      style: const TextStyle(fontSize: 32, color: Colors.blue),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      _user?['username'] ?? '',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 16,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _user?['location'] ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.phone,
                          size: 16,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _user?['phoneNumber'] ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Your Sports',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (groupedSports.isEmpty)
                    const Text('No sports selected yet.')
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
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatSportName(sport),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (isTableTennis && singles != null)
                                _ratingRow('Rating', singles)
                              else ...[
                                if (singles != null)
                                  _ratingRow('Singles', singles),
                                if (singles != null && doubles != null)
                                  const SizedBox(height: 8),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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
            color: Colors.blue,
          ),
        ),
      ],
    );
  }
}
