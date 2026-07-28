// groups_overview_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../config.dart';
import 'report_match_screen.dart';
import 'host_report_match_screen.dart';
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

      _tabController?.dispose();
      _tabController = TabController(length: _groups.length + 1, vsync: this);
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
            content: Text('Stage 2 started!'),
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
            content: Text('${data['error']} Start Stage 2 anyway?'),
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
            content: Text(data['error'] ?? 'Could not start Stage 2.'),
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
            const Tab(text: 'Stage 2'),
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
              if (hostEntersScores && widget.isHost)
                TextButton.icon(
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    final pending = schedule
                        .where((f) => f['match_status'] != 'confirmed')
                        .toList();
                    final reported = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HostReportMatchScreen(
                          leagueId: widget.leagueId,
                          sport: _league?['sport'] ?? '',
                          pendingFixtures: pending,
                          members: members,
                        ),
                      ),
                    );
                    if (reported == true) _load();
                  },
                  icon: const Icon(Icons.sports_score, size: 16),
                  label: const Text('Enter Score'),
                )
              else if (!hostEntersScores && isMemberOfGroup)
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
            ...schedule.map((f) => _buildFixtureRow(f, isDark)),
        ],
      ),
    );
  }

  Widget _buildFixtureRow(dynamic f, bool isDark) {
    final isCompleted = f['match_status'] == 'confirmed';
    final team1Won = isCompleted && f['winner_id'] == f['reported_player1_id'];
    final team2Won = isCompleted && f['winner_id'] == f['reported_player2_id'];

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
          if (isCompleted) ...[
            const SizedBox(height: 4),
            Text(
              _formatSetScores(f['set_scores']),
              style: const TextStyle(fontSize: 11, color: AppColors.textGrey),
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
            'Lock groups and finish group play before Stage 2 can start.',
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
              "The host hasn't started Stage 2 yet.",
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
                'Stage 2 is a knockout bracket.',
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
              if (hostEntersScores && widget.isHost)
                TextButton.icon(
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    final pending = _stage2Schedule
                        .where((f) => f['match_status'] != 'confirmed')
                        .toList();
                    final reported = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HostReportMatchScreen(
                          leagueId: widget.leagueId,
                          sport: _league?['sport'] ?? '',
                          pendingFixtures: pending,
                          members: _stage2Leaderboard,
                        ),
                      ),
                    );
                    if (reported == true) _load();
                  },
                  icon: const Icon(Icons.sports_score, size: 16),
                  label: const Text('Enter Score'),
                )
              else if (!hostEntersScores && isQualifier)
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
            ..._stage2Schedule.map((f) => _buildFixtureRow(f, isDark)),
        ],
      ),
    );
  }

  Widget _buildStage2SetupForm() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Set Up Stage 2', style: Theme.of(context).textTheme.titleLarge),
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
              : const Text('Start Stage 2'),
        ),
      ],
    );
  }
}
