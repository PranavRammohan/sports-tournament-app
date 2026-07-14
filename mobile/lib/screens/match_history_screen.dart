// match_history_screen.dart
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

class MatchHistoryScreen extends StatefulWidget {
  const MatchHistoryScreen({super.key});

  @override
  State<MatchHistoryScreen> createState() => _MatchHistoryScreenState();
}

class _MatchHistoryScreenState extends State<MatchHistoryScreen> {
  List<dynamic> _matches = [];
  int? _currentUserId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final userJson = prefs.getString('user');
      if (userJson != null) {
        _currentUserId = jsonDecode(userJson)['id'];
      }

      final response = await http.get(
        Uri.parse('$apiUrl/matches/history'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        setState(() => _matches = data['matches']);
      }
    } catch (err) {
      // fail silently, pull-to-refresh available
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
      if (sets.isEmpty) return '';
      return sets.map((s) => '${s['me']}-${s['opponent']}').join(', ');
    } catch (err) {
      return '';
    }
  }

  // Postgres NUMERIC columns can come back as strings in JSON (e.g. "0.10")
  // instead of actual numbers — this safely converts either case.
  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Match History')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadHistory,
              child: _matches.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: Center(
                            child: Text(
                              "You haven't played any confirmed matches yet.",
                              textAlign: TextAlign.center,
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

                        final isTeam1 =
                            m['player1_id'] == _currentUserId ||
                            m['player1_partner_id'] == _currentUserId;
                        final iWon = isTeam1
                            ? m['winner_id'] == m['player1_id']
                            : m['winner_id'] == m['player2_id'];

                        final isDoubles = m['player1_partner_username'] != null;
                        final opponentLabel = isTeam1
                            ? (isDoubles
                                  ? '${m['player2_username']} & ${m['player2_partner_username']}'
                                  : m['player2_username'])
                            : (isDoubles
                                  ? '${m['player1_username']} & ${m['player1_partner_username']}'
                                  : m['player1_username']);

                        double? ratingChange;
                        if (m['player1_id'] == _currentUserId) {
                          ratingChange = _toDouble(m['player1_rating_change']);
                        } else if (m['player2_id'] == _currentUserId) {
                          ratingChange = _toDouble(m['player2_rating_change']);
                        } else if (m['player1_partner_id'] == _currentUserId) {
                          ratingChange = _toDouble(
                            m['player1_partner_rating_change'],
                          );
                        } else if (m['player2_partner_id'] == _currentUserId) {
                          ratingChange = _toDouble(
                            m['player2_partner_rating_change'],
                          );
                        }

                        final changeText = ratingChange == null
                            ? ''
                            : (ratingChange >= 0
                                  ? '+${ratingChange.toStringAsFixed(2)}'
                                  : ratingChange.toStringAsFixed(2));
                        final changeColor = (ratingChange ?? 0) >= 0
                            ? AppColors.success
                            : AppColors.danger;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: iWon
                                  ? AppColors.success.withValues(alpha: 0.3)
                                  : AppColors.danger.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color:
                                      (iWon
                                              ? AppColors.success
                                              : AppColors.danger)
                                          .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    sportEmojis[m['sport']] ?? '🏅',
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: iWon
                                                ? AppColors.success
                                                : AppColors.danger,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            iWon ? 'WIN' : 'LOSS',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'vs $opponentLabel',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_formatSport(m['sport'])} · ${m['area']} · ${_formatSetScores(m['set_scores'])}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (ratingChange != null)
                                Text(
                                  changeText,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: changeColor,
                                  ),
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
