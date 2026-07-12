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
    // "table_tennis" -> "Table Tennis"
    return sport
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
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
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      _user?['location'] ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      _user?['phoneNumber'] ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Your Sports',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (_sports.isEmpty)
                    const Text('No sports selected yet.')
                  else
                    ..._sports.map(
                      (s) => Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text(
                            _formatSportName(s['sport']),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${s['matches_played']} matches · ${s['wins']}W ${s['losses']}L',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${s['rating']}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                              const Text(
                                'rating',
                                style: TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
