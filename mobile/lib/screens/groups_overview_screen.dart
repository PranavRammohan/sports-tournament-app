// groups_overview_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../config.dart';
import 'report_match_screen.dart';
import 'playoffs_screen.dart';

class GroupsOverviewScreen extends StatefulWidget {
  final int leagueId;
  final bool isHost;

  const GroupsOverviewScreen({
    super.key,
    required this.leagueId,
    required this.isHost,
  });

  @override
  State<GroupsOverviewScreen> createState() => _GroupsOverviewScreenState();
}

class _GroupsOverviewScreenState extends State<GroupsOverviewScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _league;
  List<dynamic> _groups = [];
  Map<int, List<dynamic>> _groupSchedules = {};
  bool _groupsLocked = false;

  bool _stage2Started = false;
  String? _stage2ScheduleType;
  int? _groupAdvanceCount;
  bool _stage2IsKnockout = false;
  List<dynamic> _stage2Leaderboard = [];
  List<dynamic> _stage2Schedule = [];

  int? _currentUserId;
  bool _loading = true;
  bool _startingStage2 = false;
  TabController? _tabController;

  // Stage 2 setup form state (host only, pre-start).
  final TextEditingController _advanceCountController = TextEditingController(
    text: '2',
  );
  String _setupScheduleType = 'knockout';
  final TextEditingController _setupMatchesPerPlayerController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _advanceCountController.dispose();
    _setupMatchesPerPlayerController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
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
      if (leagueRes.statusCode == 200) {
        _league = leagueData['league'];
      }

      final groupsRes = await http.get(
        Uri.parse('$baseApiUrl/leagues/${widget.leagueId}/groups'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final groupsData = jsonDecode(groupsRes.body);
      if (groupsRes.statusCode == 200) {
        _groups = groupsData['groups'];
        _groupsLocked = groupsData['groupsLocked'] == true;
      }

      final Map<int, List<dynamic>> schedules = {};
      for (final g in _groups) {
        final schedRes = await http.get(
          Uri.parse(
            '$baseApiUrl/leagues/${widget.leagueId}/groups/${g['id']}/schedule',
          ),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (schedRes.statusCode == 200) {
          schedules[g['id']] = jsonDecode(schedRes.body)['schedule'];
        }
      }
      _groupSchedules = schedules;

      final stage2Res = await http.get(
        Uri.parse('$baseApiUrl/leagues/${widget.leagueId}/stage2'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (stage2Res.statusCode == 200) {
        final stage2Data = jsonDecode(stage2Res.body);
        _stage2Started = stage2Data['stage2Started'] == true;
        if (_stage2Started) {
          _stage2ScheduleType = stage2Data['scheduleType'];
          _groupAdvanceCount = stage2Data['groupAdvanceCount'];
          _stage2IsKnockout = stage2Data['isKnockout'] == true;
          _stage2Leaderboard = stage2Data['leaderboard'] ?? [];

          if (!_stage2IsKnockout) {
            final stage2SchedRes = await http.get(
              Uri.parse(
                '$baseApiUrl/leagues/${widget.leagueId}/stage2/schedule',
              ),
              headers: {'Authorization': 'Bearer $token'},
            );
            if (stage2SchedRes.statusCode == 200) {
              _stage2Schedule = jsonDecode(stage2SchedRes.body)['schedule'];
            }
          }
        }
      }

      final newLength = _groups.length + 1;
      if (_tabController == null || _tabController!.length != newLength) {
        _tabController?.dispose();
        _tabController = TabController(length: newLength, vsync: this);
      }
    } catch (err) {
      // fail silently, pull-to-refresh available
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatSetScores(dynamic raw) {
    if (raw == null) return '';
    try {
      final List sets = jsonDecode(raw);
      if (sets.isEmpty) return '';
      return sets.map((s) => '${s['me']}-${s['opponent']}').join(', ');
    } catch (err) {
      return '';
    }
  }

  Future<void> _startStage2({bool force = false}) async {
    final advanceCount = int.tryParse(_advanceCountController.text.trim());
    if (advanceCount == null || advanceCount < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter how many players advance per group.'),
        ),
      );
      return;
    }
    int? matchesPerPlayer;
    if (_setupScheduleType == 'matches_per_player') {
      matchesPerPlayer = int.tryParse(
        _setupMatchesPerPlayerController.text.trim(),
      );
      if (matchesPerPlayer == null || matchesPerPlayer < 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter how many matches each player should play.'),
          ),
        );
        return;
      }
    }

    HapticFeedback.mediumImpact();
    setState(() => _startingStage2 = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final response = await http.post(
        Uri.parse('$baseApiUrl/leagues/${widget.leagueId}/stage2/start'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'advanceCount': advanceCount,
          'scheduleType': _setupScheduleType,
          'matchesPerPlayer': matchesPerPlayer,
          'force': force,
        }),
      );
      final data = jsonDecode(response.body);

      if (!mounted) return;
      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Next Round started!'),
            backgroundColor: AppColors.success,
          ),
        );
        _load();
      } else if (data['incompleteMatches'] != null) {
        setState(() => _startingStage2 = false);
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            title: const Text('Group play not finished yet'),
            content: Text('${data['error']} Start the Next Round anyway?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Start Anyway'),
              ),
            ],
          ),
        );
        if (proceed == true) {
          await _startStage2(force: true);
        }
        return;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not start the Next Round.'),
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
      if (mounted) setState(() => _startingStage2 = false);
    }
  }

  Future<void> _resetStage2() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('Reset the Next Round?'),
        content: const Text(
          'This reverses every result, rating change, and point earned in the Next Round, and wipes its schedule/bracket entirely. Group standings are untouched. You can then start the Next Round again with a different format, or leave it unstarted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Reset',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    HapticFeedback.mediumImpact();
    setState(() => _startingStage2 = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final response = await http.post(
        Uri.parse('$baseApiUrl/leagues/${widget.leagueId}/stage2/reset'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);

      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Next Round reset.'),
            backgroundColor: AppColors.success,
          ),
        );
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not reset the Next Round.'),
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
      if (mounted) setState(() => _startingStage2 = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _tabController == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Groups')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: AppColors.accent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            ..._groups.map((g) => Tab(text: g['name'])),
            const Tab(text: 'Next Round'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [..._groups.map((g) => _buildGroupTab(g)), _buildStage2Tab()],
      ),
    );
  }

  Widget _buildGroupTab(dynamic group) {
    final members = group['members'] as List;
    final schedule = _groupSchedules[group['id']] ?? [];
    final isMemberOfGroup = members.any((m) => m['id'] == _currentUserId);
    final hostEntersScores = _league?['host_enters_scores'] == true;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Standings', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (members.isEmpty)
            const Text('No players in this group yet.')
          else
            ...members.asMap().entries.map((entry) {
              final rank = entry.key + 1;
              final m = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: AppShadows.card(isDark),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      child: Text(
                        '$rank',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        m['username'],
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${m['matches_played']} matches · ${m['wins']}W ${m['losses']}L',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textGrey,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${m['points']} pts',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Schedule',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (!hostEntersScores && isMemberOfGroup)
                TextButton.icon(
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    final reported = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReportMatchScreen(
                          leagueId: widget.leagueId,
                          format: 'singles',
                          sport: _league?['sport'] ?? '',
                          members: members,
                        ),
                      ),
                    );
                    if (reported == true) _load();
                  },
                  icon: const Icon(Icons.sports_score, size: 16),
                  label: const Text('Report'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (schedule.isEmpty)
            const Text('No matches scheduled yet.')
          else
            ...schedule.map(
              (f) => _buildFixtureRow(
                f,
                isDark,
                isHost: widget.isHost,
                members: members,
              ),
            ),
        ],
      ),
    );
  }

  String _formatScheduledTime(dynamic raw) {
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw.toString())?.toLocal();
    if (dt == null) return '';
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final weekday = weekdays[dt.weekday - 1];
    final month = months[dt.month - 1];
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$weekday, $month ${dt.day} · $hour12:$minute $ampm';
  }

  Future<void> _openEditFixtureDialog(dynamic f, List<dynamic> members) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _EditGroupFixtureDialog(
        members: members,
        initialPlayer1Id: f['player1_id'],
        initialPlayer2Id: f['player2_id'],
        initialScheduledTime: f['scheduled_time'],
      ),
    );
    if (result == null) return;

    HapticFeedback.lightImpact();
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final response = await http.put(
        Uri.parse('$baseApiUrl/leagues/${widget.leagueId}/schedule/${f['id']}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'player1Id': result['player1Id'],
          'player2Id': result['player2Id'],
          'scheduledTime': result['scheduledTime'],
        }),
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Match updated.'),
            backgroundColor: AppColors.success,
          ),
        );
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not update match.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Network error.')));
    }
  }

  Future<void> _confirmDeleteFixture(int scheduledMatchId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('Remove this match?'),
        content: const Text(
          'This removes the fixture from the schedule. It has not been played yet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Remove',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    HapticFeedback.mediumImpact();
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final response = await http.delete(
        Uri.parse(
          '$baseApiUrl/leagues/${widget.leagueId}/schedule/$scheduledMatchId',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Match removed.'),
            backgroundColor: AppColors.success,
          ),
        );
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not remove match.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Network error.')));
    }
  }

  Future<void> _openEditScoreDialog(dynamic f) async {
    List<Map<String, int>>? initialSets;
    try {
      if (f['set_scores'] != null) {
        final List raw = jsonDecode(f['set_scores']);
        initialSets = raw
            .map<Map<String, int>>(
              (s) => {'me': s['me'] as int, 'opponent': s['opponent'] as int},
            )
            .toList();
      }
    } catch (err) {
      initialSets = null;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _HostScoreDialog(
        player1Name: f['player1_username'] ?? '',
        player2Name: f['player2_username'] ?? '',
        title: 'Edit Score',
        initialSets: initialSets,
      ),
    );
    if (result == null) return;

    HapticFeedback.lightImpact();
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final response = await http.put(
        Uri.parse('$baseApiUrl/matches/${f['match_id']}/edit'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(result),
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['warning'] ?? 'Score updated and ratings recalculated.',
            ),
            backgroundColor: data['warning'] != null
                ? AppColors.warning
                : AppColors.success,
          ),
        );
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not update score.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Network error.')));
    }
  }

  // Reports a brand-new result directly from a specific fixture row (host
  // mode) — no separate opponent-picking screen needed, since the fixture
  // already tells us exactly who's playing.
  Future<void> _hostReportFixture(dynamic f) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _HostScoreDialog(
        player1Name: f['player1_username'] ?? '',
        player2Name: f['player2_username'] ?? '',
        title: 'Enter Score',
      ),
    );
    if (result == null) return;

    HapticFeedback.lightImpact();
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final response = await http.post(
        Uri.parse('$baseApiUrl/matches/report-as-host'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'leagueId': widget.leagueId,
          'player1Id': f['player1_id'],
          'player1PartnerId': null,
          'player2Id': f['player2_id'],
          'player2PartnerId': null,
          'player1Units': result['player1Units'],
          'player2Units': result['player2Units'],
          'player1Won': result['player1Won'],
          'setScores': result['setScores'],
        }),
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Match confirmed!'),
            backgroundColor: AppColors.success,
          ),
        );
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not enter score.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Network error.')));
    }
  }

  Future<void> _confirmDeleteMatch(int matchId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('Delete this match result?'),
        content: const Text(
          'This reverses the rating and points changes from this match, and removes it from history. The fixture will show as not-yet-played again.',
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

    HapticFeedback.mediumImpact();
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final response = await http.delete(
        Uri.parse('$baseApiUrl/matches/$matchId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['warning'] ?? 'Match deleted.'),
            backgroundColor: data['warning'] != null
                ? AppColors.warning
                : AppColors.success,
          ),
        );
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not delete match.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Network error.')));
    }
  }

  Widget _buildFixtureRow(
    dynamic f,
    bool isDark, {
    required bool isHost,
    required List<dynamic> members,
  }) {
    final isCompleted = f['match_status'] == 'confirmed';
    final team1Won = isCompleted && f['winner_id'] == f['reported_player1_id'];
    final team2Won = isCompleted && f['winner_id'] == f['reported_player2_id'];
    final subtleColor = isDark ? Colors.grey.shade400 : AppColors.textGrey;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCompleted
              ? AppColors.success.withValues(alpha: 0.4)
              : Colors.grey.shade200,
        ),
        boxShadow: AppShadows.card(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: f['player1_username'] ?? '',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: team1Won
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: team1Won ? AppColors.success : null,
                        ),
                      ),
                      const TextSpan(text: '  vs  '),
                      TextSpan(
                        text: f['player2_username'] ?? '',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: team2Won
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: team2Won ? AppColors.success : null,
                        ),
                      ),
                    ],
                  ),
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
          if (f['scheduled_time'] != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.event, size: 12, color: subtleColor),
                const SizedBox(width: 4),
                Text(
                  _formatScheduledTime(f['scheduled_time']),
                  style: TextStyle(fontSize: 11, color: subtleColor),
                ),
              ],
            ),
          ],
          if (isCompleted) ...[
            const SizedBox(height: 4),
            Text(
              _formatSetScores(f['set_scores']),
              style: const TextStyle(fontSize: 11, color: AppColors.textGrey),
            ),
          ],
          if (isHost) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isCompleted) ...[
                  TextButton.icon(
                    onPressed: () => _openEditScoreDialog(f),
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text(
                      'Edit Score',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _confirmDeleteMatch(f['match_id']),
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 15,
                      color: AppColors.danger,
                    ),
                    label: const Text(
                      'Delete',
                      style: TextStyle(fontSize: 12, color: AppColors.danger),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ] else ...[
                  if (_league?['host_enters_scores'] == true)
                    TextButton.icon(
                      onPressed: () => _hostReportFixture(f),
                      icon: const Icon(Icons.sports_score, size: 15),
                      label: const Text(
                        'Enter Score',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  TextButton.icon(
                    onPressed: () => _openEditFixtureDialog(f, members),
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text(
                      'Edit Match',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _confirmDeleteFixture(f['id']),
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 15,
                      color: AppColors.danger,
                    ),
                    label: const Text(
                      'Remove',
                      style: TextStyle(fontSize: 12, color: AppColors.danger),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStage2Tab() {
    if (!_groupsLocked) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Lock groups and finish group play before the Next Round can start.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (!_stage2Started) {
      if (!widget.isHost) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              "The host hasn't started the Next Round yet.",
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      return _buildStage2SetupForm();
    }

    if (_stage2IsKnockout) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'The Next Round is a knockout bracket.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PlayoffsScreen(
                        leagueId: widget.leagueId,
                        isHost: widget.isHost,
                        format: 'singles',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.emoji_events_outlined),
                label: const Text('View Bracket'),
              ),
              if (widget.isHost) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _startingStage2 ? null : _resetStage2,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                  ),
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Reset Next Round'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final hostEntersScores = _league?['host_enters_scores'] == true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isQualifier = _stage2Leaderboard.any(
      (m) => m['id'] == _currentUserId,
    );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.isHost)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _startingStage2 ? null : _resetStage2,
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Reset Next Round'),
              ),
            ),
          Text('Standings', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_stage2Leaderboard.isEmpty)
            const Text('No results yet.')
          else
            ..._stage2Leaderboard.asMap().entries.map((entry) {
              final rank = entry.key + 1;
              final m = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: AppShadows.card(isDark),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      child: Text(
                        '$rank',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        m['username'],
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${m['matches_played']} matches · ${m['wins']}W ${m['losses']}L',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textGrey,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${m['points']} pts',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Schedule',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (!hostEntersScores && isQualifier)
                TextButton.icon(
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    final reported = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReportMatchScreen(
                          leagueId: widget.leagueId,
                          format: 'singles',
                          sport: _league?['sport'] ?? '',
                          members: _stage2Leaderboard,
                        ),
                      ),
                    );
                    if (reported == true) _load();
                  },
                  icon: const Icon(Icons.sports_score, size: 16),
                  label: const Text('Report'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_stage2Schedule.isEmpty)
            const Text('No matches scheduled yet.')
          else
            ..._stage2Schedule.map(
              (f) => _buildFixtureRow(
                f,
                isDark,
                isHost: widget.isHost,
                members: _stage2Leaderboard,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStage2SetupForm() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Set Up the Next Round',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose how many players advance from each group, and what format they\'ll play in this stage.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _advanceCountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Players advancing per group',
            isDense: true,
            hintText: 'e.g. 2',
          ),
        ),
        const SizedBox(height: 16),
        Text('Format', style: Theme.of(context).textTheme.titleMedium),
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          value: 'knockout',
          groupValue: _setupScheduleType,
          title: const Text('Knockout'),
          subtitle: const Text(
            'Needs an exact power-of-2 number of qualifiers',
            style: TextStyle(fontSize: 11),
          ),
          onChanged: (v) => setState(() => _setupScheduleType = v!),
        ),
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          value: 'round_robin',
          groupValue: _setupScheduleType,
          title: const Text('Round Robin'),
          subtitle: const Text(
            'Everyone plays everyone',
            style: TextStyle(fontSize: 11),
          ),
          onChanged: (v) => setState(() => _setupScheduleType = v!),
        ),
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          value: 'matches_per_player',
          groupValue: _setupScheduleType,
          title: const Text('Fixed matches per player'),
          onChanged: (v) => setState(() => _setupScheduleType = v!),
        ),
        if (_setupScheduleType == 'matches_per_player')
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: TextField(
              controller: _setupMatchesPerPlayerController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Matches per player',
                isDense: true,
                hintText: 'e.g. 3',
              ),
            ),
          ),
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          value: 'custom',
          groupValue: _setupScheduleType,
          title: const Text('Custom — I\'ll decide who plays who'),
          onChanged: (v) => setState(() => _setupScheduleType = v!),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _startingStage2 ? null : () => _startStage2(),
          child: _startingStage2
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Start Next Round'),
        ),
      ],
    );
  }
}

class _SetScore {
  final TextEditingController myScore = TextEditingController();
  final TextEditingController opponentScore = TextEditingController();
}

class _HostScoreDialog extends StatefulWidget {
  final String player1Name;
  final String player2Name;
  final String title;
  final List<Map<String, int>>? initialSets;

  const _HostScoreDialog({
    required this.player1Name,
    required this.player2Name,
    this.title = 'Enter Score',
    this.initialSets,
  });

  @override
  State<_HostScoreDialog> createState() => _HostScoreDialogState();
}

class _HostScoreDialogState extends State<_HostScoreDialog> {
  late List<_SetScore> _sets;

  @override
  void initState() {
    super.initState();
    if (widget.initialSets != null && widget.initialSets!.isNotEmpty) {
      _sets = widget.initialSets!.map((s) {
        final set = _SetScore();
        set.myScore.text = '${s['me']}';
        set.opponentScore.text = '${s['opponent']}';
        return set;
      }).toList();
    } else {
      _sets = [_SetScore()];
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._sets.asMap().entries.map((entry) {
              final index = entry.key;
              final set = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: set.myScore,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText:
                              'Game ${index + 1} — ${widget.player1Name}',
                          isDense: true,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Text('-'),
                    ),
                    Expanded(
                      child: TextField(
                        controller: set.opponentScore,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: widget.player2Name,
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_sets.length > 1)
                      IconButton(
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          color: AppColors.danger,
                        ),
                        onPressed: () => setState(() => _sets.removeAt(index)),
                      ),
                  ],
                ),
              );
            }),
            TextButton.icon(
              onPressed: () => setState(() => _sets.add(_SetScore())),
              icon: const Icon(Icons.add),
              label: const Text('Add Game'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            int totalP1 = 0;
            int totalP2 = 0;
            int setsWonByP1 = 0;
            int setsWonByP2 = 0;
            final List<Map<String, int>> setScores = [];

            for (final s in _sets) {
              final p1 = int.tryParse(s.myScore.text.trim());
              final p2 = int.tryParse(s.opponentScore.text.trim());
              if (p1 == null || p2 == null || p1 == p2) return;
              setScores.add({'me': p1, 'opponent': p2});
              totalP1 += p1;
              totalP2 += p2;
              if (p1 > p2) {
                setsWonByP1++;
              } else {
                setsWonByP2++;
              }
            }
            if (setsWonByP1 == setsWonByP2) return;

            Navigator.pop(context, {
              'player1Units': totalP1,
              'player2Units': totalP2,
              'player1Won': setsWonByP1 > setsWonByP2,
              'setScores': setScores,
            });
          },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

class _EditGroupFixtureDialog extends StatefulWidget {
  final List<dynamic> members;
  final int? initialPlayer1Id;
  final int? initialPlayer2Id;
  final dynamic initialScheduledTime;

  const _EditGroupFixtureDialog({
    required this.members,
    this.initialPlayer1Id,
    this.initialPlayer2Id,
    this.initialScheduledTime,
  });

  @override
  State<_EditGroupFixtureDialog> createState() =>
      _EditGroupFixtureDialogState();
}

class _EditGroupFixtureDialogState extends State<_EditGroupFixtureDialog> {
  int? _player1Id;
  int? _player2Id;
  DateTime? _scheduledDateTime;

  @override
  void initState() {
    super.initState();
    _player1Id = widget.initialPlayer1Id;
    _player2Id = widget.initialPlayer2Id;
    if (widget.initialScheduledTime != null) {
      _scheduledDateTime = DateTime.tryParse(
        widget.initialScheduledTime.toString(),
      )?.toLocal();
    }
  }

  List<DropdownMenuItem<int>> _items() {
    return widget.members
        .map<DropdownMenuItem<int>>(
          (m) => DropdownMenuItem(
            value: m['id'] as int,
            child: Text('${m['username']} (${m['rating']})'),
          ),
        )
        .toList();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledDateTime ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null) return;
    if (!mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _scheduledDateTime != null
          ? TimeOfDay(
              hour: _scheduledDateTime!.hour,
              minute: _scheduledDateTime!.minute,
            )
          : const TimeOfDay(hour: 18, minute: 0),
    );
    if (time == null) return;

    setState(() {
      _scheduledDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  String _formatPicked(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $hour12:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: const Text('Edit Match'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _player1Id,
              decoration: const InputDecoration(
                labelText: 'Player 1',
                isDense: true,
              ),
              items: _items(),
              onChanged: (v) => setState(() => _player1Id = v),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: _player2Id,
              decoration: const InputDecoration(
                labelText: 'Player 2',
                isDense: true,
              ),
              items: _items(),
              onChanged: (v) => setState(() => _player2Id = v),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Date & Time (optional)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _scheduledDateTime != null
                        ? _formatPicked(_scheduledDateTime!)
                        : 'Not set',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: _pickDateTime,
                  child: Text(_scheduledDateTime != null ? 'Change' : 'Set'),
                ),
                if (_scheduledDateTime != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Clear',
                    onPressed: () => setState(() => _scheduledDateTime = null),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_player1Id == null ||
                _player2Id == null ||
                _player1Id == _player2Id) {
              return;
            }
            Navigator.pop(context, {
              'player1Id': _player1Id,
              'player2Id': _player2Id,
              'scheduledTime': _scheduledDateTime?.toIso8601String(),
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
