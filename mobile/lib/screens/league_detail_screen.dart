// league_detail_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import 'report_match_screen.dart';
import 'schedule_screen.dart';

const String apiUrl = 'http://localhost:3000/api';

const Map<String, String> sportEmojis = {
  'badminton': '🏸',
  'tennis': '🎾',
  'table_tennis': '🏓',
  'pickleball': '🥒',
};

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
  int? _currentUserId;
  bool _loading = true;
  bool _deleting = false;
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
      final userJson = prefs.getString('user');
      if (userJson != null) {
        final userData = jsonDecode(userJson);
        _currentUserId = userData['id'];
      }

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

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete this league?'),
        content: const Text(
          'This will permanently delete the league, its schedule, and all match history. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _deleting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.delete(
        Uri.parse('$apiUrl/leagues/${widget.leagueId}'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;
      if (response.statusCode == 200) {
        Navigator.pop(context, 'deleted');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not delete league.'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
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
    } finally {
      if (mounted) setState(() => _deleting = false);
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
    final isHost = _league != null && _league!['created_by'] == _currentUserId;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _league != null
              ? '${_formatSport(_league!['sport'])} · ${_league!['area']}'
              : 'League',
        ),
        actions: [
          if (isHost)
            IconButton(
              icon: _deleting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.delete_outline),
              onPressed: _deleting ? null : _confirmDelete,
              tooltip: 'Delete league',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : RefreshIndicator(
              onRefresh: _loadLeague,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Text(
                          sportEmojis[_league!['sport']] ?? '🏅',
                          style: const TextStyle(fontSize: 36),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_league!['season_start']} to ${_league!['season_end']}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_leaderboard.length} players · ${_league!['format']} · ${_league!['gender_category'] == 'mens' ? "Men's" : "Women's"}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ScheduleScreen(
                            leagueId: widget.leagueId,
                            isHost: isHost,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('View Schedule'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Leaderboard',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if (_leaderboard.isEmpty)
                    Text(
                      'No members yet.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
                  else
                    ..._leaderboard.asMap().entries.map((entry) {
                      final rank = entry.key + 1;
                      final player = entry.value;
                      final rankColor = rank == 1
                          ? const Color(0xFFFFC107)
                          : rank == 2
                          ? const Color(0xFFB0BEC5)
                          : rank == 3
                          ? const Color(0xFFCD7F32)
                          : AppColors.primary.withValues(alpha: 0.15);
                      final rankTextColor = rank <= 3
                          ? Colors.white
                          : AppColors.primary;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: rankColor,
                            child: Text(
                              '$rank',
                              style: TextStyle(
                                color: rankTextColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 24),
                  Text(
                    'Match History',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if (_matchHistory.isEmpty)
                    Text(
                      'No matches played yet.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
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

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  team1Name,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: team1Won
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: team1Won
                                        ? AppColors.success
                                        : AppColors.textDark,
                                  ),
                                ),
                                Text(
                                  '  vs  ',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                Text(
                                  team2Name,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: team2Won
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: team2Won
                                        ? AppColors.success
                                        : AppColors.textDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatSetScores(m['set_scores']),
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
