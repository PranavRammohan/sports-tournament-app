// pending_matches_screen.dart
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

class PendingMatchesScreen extends StatefulWidget {
  const PendingMatchesScreen({super.key});

  @override
  State<PendingMatchesScreen> createState() => _PendingMatchesScreenState();
}

class _PendingMatchesScreenState extends State<PendingMatchesScreen> {
  List<dynamic> _matches = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  Future<void> _loadMatches() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.get(
        Uri.parse('$apiUrl/matches/pending'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        setState(() => _matches = data['matches']);
      }
    } catch (err) {
      // fail silently
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _confirmMatch(int matchId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.post(
        Uri.parse('$apiUrl/matches/$matchId/confirm'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Match confirmed! Ratings updated.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.success,
          ),
        );
        _loadMatches();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not confirm.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Network error.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _formatSport(String sport) => sport
      .split('_')
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  String _formatSetScores(dynamic rawSetScores, bool reportedByPlayer1) {
    try {
      final List sets = jsonDecode(rawSetScores);
      if (sets.isEmpty) return 'No score breakdown available.';
      return sets
          .map((s) {
            final mine = s['me'];
            final theirs = s['opponent'];
            return reportedByPlayer1 ? '$mine-$theirs' : '$theirs-$mine';
          })
          .join(', ');
    } catch (err) {
      return 'Score unavailable.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pending Confirmations')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadMatches,
              child: _matches.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: Center(
                            child: Text(
                              'Nothing waiting on you right now.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: _matches.length,
                      itemBuilder: (context, index) {
                        final m = _matches[index];
                        final isDoubles = m['league_format'] == 'doubles';

                        final team1 = isDoubles
                            ? '${m['player1_username']} & ${m['player1_partner_username'] ?? '?'}'
                            : m['player1_username'];
                        final team2 = isDoubles
                            ? '${m['player2_username']} & ${m['player2_partner_username'] ?? '?'}'
                            : m['player2_username'];

                        final reportedByPlayer1 =
                            m['reported_by'] == m['player1_id'];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.accent.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    sportEmojis[m['sport']] ?? '🏅',
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _formatSport(m['sport']),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '$team1  vs  $team2',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatSetScores(
                                  m['set_scores'],
                                  reportedByPlayer1,
                                ),
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 14),
                              ElevatedButton(
                                onPressed: () => _confirmMatch(m['id']),
                                child: const Text('Confirm Result'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
