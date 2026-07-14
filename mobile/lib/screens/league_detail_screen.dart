// league_detail_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'report_match_screen.dart';

const String apiUrl = 'http://localhost:3000/api';

class LeagueDetailScreen extends StatefulWidget {
  final int leagueId;

  const LeagueDetailScreen({super.key, required this.leagueId});

  @override
  State<LeagueDetailScreen> createState() => _LeagueDetailScreenState();
}

class _LeagueDetailScreenState extends State<LeagueDetailScreen> {
  Map<String, dynamic>? _league;
  List<dynamic> _leaderboard = [];
  List<dynamic> _matchHistory = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLeague();
  }

  Future<void> _loadLeague() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.get(
        Uri.parse('$apiUrl/leagues/${widget.leagueId}'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);

      if (response.statusCode != 200) {
        setState(() => _error = data['error'] ?? 'Could not load league.');
        return;
      }

      setState(() {
        _league = data['league'];
        _leaderboard = data['leaderboard'];
      });

      final historyResponse = await http.get(
        Uri.parse('$apiUrl/leagues/${widget.leagueId}/matches'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final historyData = jsonDecode(historyResponse.body);
      if (historyResponse.statusCode == 200) {
        setState(() => _matchHistory = historyData['matches']);
      }
    } catch (err) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      setState(() => _loading = false);
    }
  }

  String _formatSport(String sport) => sport
      .split('_')
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  String _formatSetScores(dynamic rawSetScores) {
    try {
      final List sets = jsonDecode(rawSetScores);
      if (sets.isEmpty) return 'No score breakdown available.';
      return sets.map((s) => '${s['me']}-${s['opponent']}').join(', ');
    } catch (err) {
      return 'Score unavailable.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _league != null
              ? '${_formatSport(_league!['sport'])} · ${_league!['area']}'
              : 'League',
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : RefreshIndicator(
              onRefresh: _loadLeague,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Season: ${_league!['season_start']} to ${_league!['season_end']}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_leaderboard.length} players · ${_league!['format']} · ${_league!['gender_category']}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final reported = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ReportMatchScreen(
                            leagueId: widget.leagueId,
                            format: _league!['format'],
                            sport: _league!['sport'],
                            members: _leaderboard,
                          ),
                        ),
                      );
                      if (reported == true) _loadLeague();
                    },
                    icon: const Icon(Icons.sports_score),
                    label: const Text('Report a Match'),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Leaderboard',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (_leaderboard.isEmpty)
                    const Text('No members yet.')
                  else
                    ..._leaderboard.asMap().entries.map((entry) {
                      final rank = entry.key + 1;
                      final player = entry.value;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: rank == 1
                                ? Colors.amber
                                : rank == 2
                                ? Colors.grey.shade400
                                : rank == 3
                                ? Colors.brown.shade300
                                : Colors.blue.shade100,
                            child: Text('$rank'),
                          ),
                          title: Text(
                            player['username'],
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${player['matches_played']} matches · ${player['wins']}W ${player['losses']}L',
                          ),
                          trailing: Text(
                            '${player['rating']}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 24),
                  const Text(
                    'Match History',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (_matchHistory.isEmpty)
                    const Text('No matches played yet.')
                  else
                    ..._matchHistory.map((m) {
                      final isDoubles = m['player1_partner_username'] != null;
                      final team1Name = isDoubles
                          ? '${m['player1_username']} & ${m['player1_partner_username']}'
                          : m['player1_username'];
                      final team2Name = isDoubles
                          ? '${m['player2_username']} & ${m['player2_partner_username']}'
                          : m['player2_username'];

                      final winnerId = m['winner_id'];
                      final team1Won = winnerId == m['player1_id'];
                      final team2Won = winnerId == m['player2_id'];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RichText(
                                text: TextSpan(
                                  style: DefaultTextStyle.of(context).style,
                                  children: [
                                    TextSpan(
                                      text: team1Name,
                                      style: TextStyle(
                                        fontWeight: team1Won
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: team1Won
                                            ? Colors.green.shade700
                                            : null,
                                      ),
                                    ),
                                    const TextSpan(text: '  vs  '),
                                    TextSpan(
                                      text: team2Name,
                                      style: TextStyle(
                                        fontWeight: team2Won
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: team2Won
                                            ? Colors.green.shade700
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatSetScores(m['set_scores']),
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
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
}
