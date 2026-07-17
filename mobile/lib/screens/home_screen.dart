// home_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../config.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _username = '';
  int _leagueCount = 0;
  int _matchesPlayed = 0;
  int _wins = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final userJson = prefs.getString('user');
      if (userJson != null) {
        _username = jsonDecode(userJson)['username'] ?? '';
      }

      final leaguesRes = await http.get(
        Uri.parse('$baseApiUrl/leagues/mine'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final leaguesData = jsonDecode(leaguesRes.body);
      if (leaguesRes.statusCode == 200) {
        _leagueCount = (leaguesData['leagues'] as List).length;
      }

      final sportsRes = await http.get(
        Uri.parse('$baseApiUrl/sports/mine'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final sportsData = jsonDecode(sportsRes.body);
      if (sportsRes.statusCode == 200) {
        final Map<String, dynamic> seenSports = {};
        for (final row in sportsData['sports']) {
          seenSports[row['sport']] = row;
        }
        _matchesPlayed = seenSports.values.fold<int>(
          0,
          (sum, r) => sum + (r['matches_played'] as int),
        );
        _wins = seenSports.values.fold<int>(
          0,
          (sum, r) => sum + (r['wins'] as int),
        );
      }
    } catch (err) {
      // fail silently
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final winRate = _matchesPlayed == 0
        ? 0
        : ((_wins / _matchesPlayed) * 100).round();

    return Scaffold(
      appBar: AppBar(title: const Text('RallyX')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Welcome back, $_username',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _statCard('Leagues', '$_leagueCount')),
                      const SizedBox(width: 10),
                      Expanded(child: _statCard('Matches', '$_matchesPlayed')),
                      const SizedBox(width: 10),
                      Expanded(child: _statCard('Win rate', '$winRate%')),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _statCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
