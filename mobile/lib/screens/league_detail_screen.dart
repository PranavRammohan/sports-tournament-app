// league_detail_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../config.dart';
import '../utils.dart';
import '../widgets/sport_icon.dart';
import 'report_match_screen.dart';
import 'host_report_match_screen.dart';
import 'playoffs_screen.dart';

class LeagueDetailScreen extends StatefulWidget {
  final int leagueId;

  const LeagueDetailScreen({super.key, required this.leagueId});

  @override
  State<LeagueDetailScreen> createState() => _LeagueDetailScreenState();
}

class _LeagueDetailScreenState extends State<LeagueDetailScreen> {
  Map<String, dynamic>? _league;
  List<dynamic> _leaderboard = [];
  List<dynamic> _schedule = [];
  int? _currentUserId;
  bool _loading = true;
  bool _deleting = false;
  bool _leaving = false;
  bool _joining = false;
  bool _generating = false;
  String? _error;

  bool get _isMember =>
      _currentUserId != null &&
      _leaderboard.any((p) => p['id'] == _currentUserId);

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
        Uri.parse('$baseApiUrl/leagues/${widget.leagueId}'),
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

      final scheduleRes = await http.get(
        Uri.parse('$baseApiUrl/leagues/${widget.leagueId}/schedule'),
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

  Future<void> _joinLeague() async {
    setState(() => _joining = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.post(
        Uri.parse('$baseApiUrl/leagues/${widget.leagueId}/join'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);

      if (!mounted) return;
      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Joined league!'),
            backgroundColor: AppColors.success,
          ),
        );
        await _loadAll();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not join.'),
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
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _generateSchedule() async {
    setState(() => _generating = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.post(
        Uri.parse('$baseApiUrl/leagues/${widget.leagueId}/generate-schedule'),
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
        Uri.parse('$baseApiUrl/leagues/${widget.leagueId}'),
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

  Future<void> _confirmLeave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('Leave this league?'),
        content: const Text('You can rejoin later if you change your mind.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Leave',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _leaving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final response = await http.post(
        Uri.parse('$baseApiUrl/leagues/${widget.leagueId}/leave'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);

      if (!mounted) return;
      if (response.statusCode == 200) {
        Navigator.pop(context, 'left');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not leave league.'),
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
      if (mounted) setState(() => _leaving = false);
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

  Widget? _buildActionButton(bool isHost) {
    final hostEntersScores = _league!['host_enters_scores'] == true;

    if (hostEntersScores) {
      if (!isHost) return null;

      final pendingFixtures = _schedule
          .where((f) => f['match_status'] != 'confirmed')
          .toList();

      return FloatingActionButton.extended(
        onPressed: () async {
          final reported = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => HostReportMatchScreen(
                leagueId: widget.leagueId,
                sport: _league!['sport'],
                pendingFixtures: pendingFixtures,
              ),
            ),
          );
          if (reported == true) _loadAll();
        },
        icon: const Icon(Icons.sports_score),
        label: const Text('Enter Score'),
      );
    }

    if (!_isMember) return null;

    return FloatingActionButton.extended(
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
    );
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
          title: Row(
            children: [
              sportIcon(_league!['sport'], size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(_league!['name'], overflow: TextOverflow.ellipsis),
              ),
            ],
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
              )
            else if (_isMember)
              IconButton(
                icon: _leaving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.exit_to_app),
                onPressed: _leaving ? null : _confirmLeave,
                tooltip: 'Leave league',
              ),
          ],
          bottom: const TabBar(
            indicatorColor: AppColors.accent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Leaderboard'),
              Tab(text: 'Schedule'),
              Tab(text: 'My Matches'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildLeaderboardTab(isHost),
            _buildScheduleTab(),
            _buildMyMatchesTab(),
          ],
        ),
        floatingActionButton: _buildActionButton(isHost),
      ),
    );
  }

  Widget _buildLeaderboardTab(bool isHost) {
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_formatSport(_league!['sport'])} · ${_league!['area']}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatDateOnly(_league!['season_start'])} to ${formatDateOnly(_league!['season_end'])} · ${_leaderboard.length} players · ${_league!['format']} · ${_league!['gender_category'] == 'mens' ? "Men's" : "Women's"}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Ranked by league points (win = 2, +1 for a dominant win)',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textGrey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          if (!_isMember)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ElevatedButton.icon(
                onPressed: _joining ? null : _joinLeague,
                icon: _joining
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.add),
                label: const Text('Join League'),
              ),
            ),
          if (_isMember && _league!['format'] == 'singles')
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PlayoffsScreen(
                        leagueId: widget.leagueId,
                        isHost: isHost,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.emoji_events_outlined),
                label: const Text('Playoffs'),
              ),
            ),
          if (isHost && _schedule.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ElevatedButton(
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
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${player['points']} pts',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.accent,
                        ),
                      ),
                      Text(
                        'Rating: ${player['rating']}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildScheduleTab() {
    if (!_isMember) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Join this league to see the schedule.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    if (_schedule.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _league!['created_by'] == _currentUserId
                ? 'No schedule yet. Generate one from the Leaderboard tab.'
                : "The host hasn't generated a schedule yet.",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
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
                ...entry.value.map(
                  (f) => _buildFixtureCard(f, showContacts: true),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMyMatchesTab() {
    if (!_isMember) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Join this league to see your matches.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    final myFixtures = _schedule.where((f) {
      return [
        f['player1_id'],
        f['player1_partner_id'],
        f['player2_id'],
        f['player2_partner_id'],
      ].contains(_currentUserId);
    }).toList();

    if (myFixtures.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No scheduled matches for you yet.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: myFixtures
            .map((f) => _buildFixtureCard(f, showContacts: true))
            .toList(),
      ),
    );
  }

  Widget _buildFixtureCard(dynamic f, {required bool showContacts}) {
    final isDoubles = f['player1_partner_username'] != null;
    final team1 = isDoubles
        ? '${f['player1_username']} & ${f['player1_partner_username']}'
        : f['player1_username'];
    final team2 = isDoubles
        ? '${f['player2_username']} & ${f['player2_partner_username']}'
        : f['player2_username'];
    final isCompleted = f['match_status'] == 'confirmed';
    final team1Won = isCompleted && f['winner_id'] == f['reported_player1_id'];
    final team2Won = isCompleted && f['winner_id'] == f['reported_player2_id'];

    final involvesMe = [
      f['player1_id'],
      f['player1_partner_id'],
      f['player2_id'],
      f['player2_partner_id'],
    ].contains(_currentUserId);
    final iAmTeam1 =
        f['player1_id'] == _currentUserId ||
        f['player1_partner_id'] == _currentUserId;

    final List<Map<String, String>> opponentContacts = [];
    if (showContacts && involvesMe && !isCompleted) {
      if (iAmTeam1) {
        if (f['player2_phone'] != null) {
          opponentContacts.add({
            'name': f['player2_username'],
            'phone': f['player2_phone'],
          });
        }
        if (f['player2_partner_phone'] != null) {
          opponentContacts.add({
            'name': f['player2_partner_username'],
            'phone': f['player2_partner_phone'],
          });
        }
      } else {
        if (f['player1_phone'] != null) {
          opponentContacts.add({
            'name': f['player1_username'],
            'phone': f['player1_phone'],
          });
        }
        if (f['player1_partner_phone'] != null) {
          opponentContacts.add({
            'name': f['player1_partner_username'],
            'phone': f['player1_partner_phone'],
          });
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCompleted
              ? AppColors.success.withValues(alpha: 0.4)
              : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: isCompleted
                    ? Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: team1,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: team1Won
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: team1Won
                                    ? AppColors.success
                                    : AppColors.textDark,
                              ),
                            ),
                            const TextSpan(
                              text: '  vs  ',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textGrey,
                              ),
                            ),
                            TextSpan(
                              text: team2,
                              style: TextStyle(
                                fontSize: 13,
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
                      )
                    : Text(
                        '$team1 vs $team2',
                        style: const TextStyle(fontSize: 13),
                      ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
                    color: isCompleted ? AppColors.success : AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
          if (isCompleted) ...[
            const SizedBox(height: 4),
            Text(
              _formatSetScores(f['set_scores']),
              style: const TextStyle(fontSize: 11, color: AppColors.textGrey),
            ),
          ],
          if (opponentContacts.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...opponentContacts.map(
              (c) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    const Icon(
                      Icons.phone,
                      size: 12,
                      color: AppColors.textGrey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${c['name']}: ${c['phone']}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
