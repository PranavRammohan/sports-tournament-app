// league_detail_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
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
  List<dynamic> _schedule = [];
  int? _currentUserId;
  bool _loading = true;
  bool _deleting = false;
  bool _generating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final userJson = prefs.getString('user');
      if (userJson != null) {
        _currentUserId = jsonDecode(userJson)['id'];
      }

      final leagueRes = await http.get(
        Uri.parse('$apiUrl/leagues/${widget.leagueId}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final leagueData = jsonDecode(leagueRes.body);
      if (leagueRes.statusCode != 200) {
        setState(
          () => _error = leagueData['error'] ?? 'Could not load league.',
        );
        return;
      }
      setState(() {
        _league = leagueData['league'];
        _leaderboard = leagueData['leaderboard'];
      });

      final historyRes = await http.get(
        Uri.parse('$apiUrl/leagues/${widget.leagueId}/matches'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final historyData = jsonDecode(historyRes.body);
      if (historyRes.statusCode == 200) {
        setState(() => _matchHistory = historyData['matches']);
      }

      final scheduleRes = await http.get(
        Uri.parse('$apiUrl/leagues/${widget.leagueId}/schedule'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final scheduleData = jsonDecode(scheduleRes.body);
      if (scheduleRes.statusCode == 200) {
        setState(() => _schedule = scheduleData['schedule']);
      }
    } catch (err) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _generateSchedule() async {
    setState(() => _generating = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.post(
        Uri.parse('$apiUrl/leagues/${widget.leagueId}/generate-schedule'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);

      if (!mounted) return;
      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Schedule generated: ${data['matchCount']} matches'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadAll();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not generate schedule.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Network error.')));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('Delete this league?'),
        content: const Text(
          'This permanently deletes the league, its schedule, and all match history.',
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
          ),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Network error.')));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  String _formatSport(String sport) => sport
      .split('_')
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  String _formatSetScores(dynamic raw) {
    try {
      final List sets = jsonDecode(raw);
      if (sets.isEmpty) return '';
      return sets.map((s) => '${s['me']}-${s['opponent']}').join(', ');
    } catch (err) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHost = _league != null && _league!['created_by'] == _currentUserId;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('League')),
        body: Center(child: Text(_error!)),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${_formatSport(_league!['sport'])} · ${_league!['area']}',
          ),
          actions: [
            if (isHost)
              IconButton(
                icon: _deleting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.delete_outline),
                onPressed: _deleting ? null : _confirmDelete,
              ),
          ],
          bottom: const TabBar(
            indicatorColor: AppColors.accent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Leaderboard'),
              Tab(text: 'Schedule'),
              Tab(text: 'History'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildLeaderboardTab(),
            _buildScheduleTab(),
            _buildHistoryTab(),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
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
            if (reported == true) _loadAll();
          },
          icon: const Icon(Icons.sports_score),
          label: const Text('Report'),
        ),
      ),
    );
  }

  Widget _buildLeaderboardTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              '${_league!['season_start']} to ${_league!['season_end']} · ${_leaderboard.length} players · ${_league!['format']} · ${_league!['gender_category'] == 'mens' ? "Men's" : "Women's"}',
              style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
            ),
          ),
          if (_leaderboard.isEmpty)
            const Text('No members yet.')
          else
            ..._leaderboard.asMap().entries.map((entry) {
              final rank = entry.key + 1;
              final player = entry.value;
              final rankColor = rank == 1
                  ? const Color(0xFFB8860B)
                  : rank == 2
                  ? const Color(0xFF9CA3AF)
                  : rank == 3
                  ? const Color(0xFFB08D57)
                  : Colors.grey.shade200;
              final rankTextColor = rank <= 3
                  ? Colors.white
                  : AppColors.textDark;

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 0,
                  ),
                  leading: CircleAvatar(
                    radius: 15,
                    backgroundColor: rankColor,
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        color: rankTextColor,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    player['username'],
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    '${player['matches_played']} matches · ${player['wins']}W ${player['losses']}L',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Text(
                    '${player['rating']}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildScheduleTab() {
    if (_schedule.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _league!['created_by'] == _currentUserId
                    ? 'No schedule yet.'
                    : "The host hasn't generated a schedule yet.",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (_league!['created_by'] == _currentUserId) ...[
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: _generating ? null : _generateSchedule,
                  child: _generating
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Generate Schedule'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final Map<int, List<dynamic>> tiers = {};
    for (final f in _schedule) {
      tiers.putIfAbsent(f['tier_number'], () => []).add(f);
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: tiers.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tier ${entry.key}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ...entry.value.map((f) {
                  final isDoubles = f['player1_partner_username'] != null;
                  final team1 = isDoubles
                      ? '${f['player1_username']} & ${f['player1_partner_username']}'
                      : f['player1_username'];
                  final team2 = isDoubles
                      ? '${f['player2_username']} & ${f['player2_partner_username']}'
                      : f['player2_username'];
                  final isCompleted = f['match_status'] == 'confirmed';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isCompleted
                            ? AppColors.success.withValues(alpha: 0.4)
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$team1 vs $team2',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isCompleted
                                ? AppColors.success.withValues(alpha: 0.1)
                                : AppColors.warning.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isCompleted ? 'Done' : 'Pending',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isCompleted
                                  ? AppColors.success
                                  : AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHistoryTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: _matchHistory.isEmpty
          ? ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No matches played yet.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _matchHistory.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final m = _matchHistory[index];
                final isDoubles = m['player1_partner_username'] != null;
                final team1 = isDoubles
                    ? '${m['player1_username']} & ${m['player1_partner_username']}'
                    : m['player1_username'];
                final team2 = isDoubles
                    ? '${m['player2_username']} & ${m['player2_partner_username']}'
                    : m['player2_username'];
                final team1Won = m['winner_id'] == m['player1_id'];

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textDark,
                            ),
                            children: [
                              TextSpan(
                                text: team1,
                                style: TextStyle(
                                  fontWeight: team1Won
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: team1Won
                                      ? AppColors.success
                                      : AppColors.textDark,
                                ),
                              ),
                              const TextSpan(text: '  vs  '),
                              TextSpan(
                                text: team2,
                                style: TextStyle(
                                  fontWeight: !team1Won
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: !team1Won
                                      ? AppColors.success
                                      : AppColors.textDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Text(
                        _formatSetScores(m['set_scores']),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
