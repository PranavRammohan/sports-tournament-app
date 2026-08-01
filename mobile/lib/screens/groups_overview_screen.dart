// groups_overview_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../api_client.dart';
import 'report_match_screen.dart';
import '../widgets/bracket_view.dart';
import '../widgets/match_badges.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/friendly_empty_state.dart';
import 'add_manual_match_screen.dart';

class GroupsOverviewScreen extends StatefulWidget {
  final int leagueId;
  final bool isHost;
  // Groups can nest inside other groups (see backend/leagueRoutes.js's
  // buildGroupTree). Null = show the league's top-level groups, exactly as
  // before nesting existed. Non-null = this screen has been pushed by
  // tapping a "Groups inside" card and shows that one specific group's own
  // content directly (no tab bar needed — there's exactly one group to
  // show), with `title` as the AppBar/breadcrumb text.
  final int? parentGroupId;
  final String? title;

  const GroupsOverviewScreen({
    super.key,
    required this.leagueId,
    required this.isHost,
    this.parentGroupId,
    this.title,
  });

  @override
  State<GroupsOverviewScreen> createState() => _GroupsOverviewScreenState();
}

class _GroupsOverviewScreenState extends State<GroupsOverviewScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _league;
  List<dynamic> _groups = [];
  Map<int, List<dynamic>> _groupSchedules = {};

  // Tennis is scored in "Sets"; everything else in this app is "Games".
  String get _unitLabel => _league?['sport'] == 'tennis' ? 'Set' : 'Game';

  bool get _isDoubles => _league?['format'] == 'doubles';

  // "Alice & Bob" for a doubles team, or just the one name for singles.
  String _teamLabel(String? username, String? partnerUsername) {
    final name = username ?? '';
    return partnerUsername != null ? '$name & $partnerUsername' : name;
  }

  // Mirrors group_management_screen.dart's _displayUnits: a group's member
  // list carries both partners of a doubles team as separate entries
  // (always sharing identical group_ids/stats), so standings collapse that
  // down to one row per team. Singles is unchanged, just with a displayName
  // added so rendering stays uniform.
  List<dynamic> _displayUnits(List<dynamic> members) {
    if (!_isDoubles) {
      return members.map((m) => {...m, 'displayName': m['username']}).toList();
    }
    final seen = <int>{};
    final units = <dynamic>[];
    for (final m in members) {
      if (seen.contains(m['id'])) continue;
      seen.add(m['id'] as int);
      dynamic partner;
      if (m['partner_id'] != null) {
        for (final candidate in members) {
          if (candidate['id'] == m['partner_id']) {
            partner = candidate;
            break;
          }
        }
        if (partner != null) seen.add(partner['id'] as int);
      }
      units.add({
        ...m,
        'displayName': _teamLabel(m['username'], partner?['username']),
      });
    }
    return units;
  }

  // Mirrors the backend's resolvePointsConfig: a group's own points_enabled
  // wins if set, otherwise it inherits the tournament's setting.
  bool _groupPointsEnabled(dynamic group) {
    if (group['points_enabled'] != null) return group['points_enabled'] == true;
    return _league?['points_enabled'] != false;
  }

  int? _currentUserId;
  bool _loading = true;
  String? _error;
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  // Recursively searches the fetched tree for the node with this id — used
  // when this screen was pushed scoped to one specific group (parentGroupId
  // set), since GET /groups always returns the whole tree from the league's
  // top-level groups down, not a subtree scoped to one id.
  dynamic _findNodeById(List<dynamic> nodes, int id) {
    for (final node in nodes) {
      if (node['id'] == id) return node;
      final children = node['children'] as List?;
      if (children != null && children.isNotEmpty) {
        final found = _findNodeById(children, id);
        if (found != null) return found;
      }
    }
    return null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // League and groups don't depend on each other — fetch concurrently.
      final results = await Future.wait([
        ApiClient.get('/leagues/${widget.leagueId}'),
        ApiClient.get('/leagues/${widget.leagueId}/groups'),
      ]);
      final leagueRes = results[0];
      final groupsRes = results[1];

      if (leagueRes.statusCode == 200) {
        _league = leagueRes.data['league'];
      }

      if (groupsRes.statusCode == 200) {
        final tree = groupsRes.data['groups'] as List;
        if (widget.parentGroupId == null) {
          // Top level: one tab per top-level group, exactly as before
          // nesting existed.
          _groups = tree;
        } else {
          // Scoped to one specific group — show just that node (its own
          // content, plus its children as "Groups inside" cards within
          // _buildGroupTab). Not found (e.g. deleted concurrently) falls
          // through to the existing empty state.
          final scoped = _findNodeById(tree, widget.parentGroupId!);
          _groups = scoped != null ? [scoped] : [];
        }
      }

      // Each non-knockout group's schedule fetch is independent of the
      // others too — knockout groups render a bracket instead (fetched by
      // BracketView itself when the host/player opens that group's tab).
      // Only fetched for the groups this screen instance actually renders
      // (_groups above) — a deeper group's schedule is fetched by its own
      // screen instance once the user drills into it.
      final scheduledGroups = _groups.where((g) => g['schedule_type'] != 'knockout').toList();
      if (scheduledGroups.isNotEmpty) {
        final schedResults = await Future.wait(
          scheduledGroups.map(
            (g) => ApiClient.get('/leagues/${widget.leagueId}/groups/${g['id']}/schedule'),
          ),
        );
        final Map<int, List<dynamic>> schedules = {};
        for (var i = 0; i < scheduledGroups.length; i++) {
          final schedRes = schedResults[i];
          if (schedRes.statusCode == 200) {
            schedules[scheduledGroups[i]['id']] = schedRes.data['schedule'];
          }
        }
        _groupSchedules = schedules;
      }

      // A scoped single-group view never needs a tab bar (there's exactly
      // one thing to show), so no TabController is built for it.
      final newLength = _groups.length;
      if (widget.parentGroupId == null &&
          newLength > 0 &&
          (_tabController == null || _tabController!.length != newLength)) {
        _tabController?.dispose();
        _tabController = TabController(length: newLength, vsync: this);
      }
    } catch (err) {
      setState(() => _error = 'Could not reach the server.');
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

  String _formatLabel(dynamic group) {
    switch (group['schedule_type']) {
      case 'matches_per_player':
        return '${group['matches_per_player']} matches/player';
      case 'knockout':
        return 'Knockout';
      case 'custom':
        return 'Custom';
      default:
        return 'Round Robin';
    }
  }

  @override
  Widget build(BuildContext context) {
    final appBarTitle = widget.title ?? 'Groups';

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(appBarTitle)),
        body: const SkeletonList(),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(appBarTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }
    if (_groups.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(appBarTitle)),
        body: FriendlyEmptyState(
          icon: Icons.groups_outlined,
          title: widget.parentGroupId != null ? 'Group not found' : 'No groups yet',
          subtitle: widget.parentGroupId != null
              ? 'This group may have been deleted or moved.'
              : (widget.isHost
                  ? 'Create one from Manage Groups to get started.'
                  : "The host hasn't created any groups yet."),
        ),
      );
    }

    // Scoped to one specific group (pushed from a "Groups inside" card) —
    // exactly one thing to show, so no tab bar, just its content directly.
    if (widget.parentGroupId != null) {
      return Scaffold(
        appBar: AppBar(title: Text(appBarTitle)),
        body: _buildGroupTab(_groups.first),
      );
    }

    if (_tabController == null) {
      return Scaffold(
        appBar: AppBar(title: Text(appBarTitle)),
        body: const SkeletonList(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: AppColors.accent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: _groups.map<Tab>((g) => Tab(text: g['name'])).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _groups.map<Widget>((g) => _buildGroupTab(g)).toList(),
      ),
    );
  }

  // Standings rows for a member list — used both for a group's own roster
  // and (via combinedMembers) for the roll-up shown under "Groups inside"
  // when a group has children. `group` supplies the points-enabled setting
  // and display-unit logic, independent of which member list is passed.
  List<Widget> _buildStandingsRows(List<dynamic> members, dynamic group, bool isDark) {
    if (members.isEmpty) {
      return [
        Text(_isDoubles ? 'No teams in this group yet.' : 'No players in this group yet.'),
      ];
    }
    final pointsEnabled = _groupPointsEnabled(group);
    return _displayUnits(members).asMap().entries.map<Widget>((entry) {
      final rank = entry.key + 1;
      final m = entry.value;
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.cardBorder(isDark)),
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
                m['displayName'],
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '${m['matches_played']} matches · ${m['wins']}W ${m['losses']}L',
              style: const TextStyle(fontSize: 11, color: AppColors.textGrey),
            ),
            if (pointsEnabled) ...[
              const SizedBox(width: 10),
              PointsBadge(points: m['points'], fontSize: 14),
            ],
          ],
        ),
      );
    }).toList();
  }

  // Card for a child group shown under "Groups inside" — tapping drills
  // into that group's own GroupsOverviewScreen (its own content, plus its
  // own "Groups inside" section if it has further children).
  Widget _buildChildGroupCard(dynamic child) {
    final childCount = (child['children'] as List?)?.length ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          childCount > 0 ? Icons.folder_outlined : Icons.groups_outlined,
          color: AppColors.accent,
        ),
        title: Text(
          child['name'] ?? '',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          childCount > 0
              ? '$childCount group${childCount == 1 ? '' : 's'} inside · ${_formatLabel(child)}'
              : _formatLabel(child),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          HapticFeedback.selectionClick();
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GroupsOverviewScreen(
                leagueId: widget.leagueId,
                isHost: widget.isHost,
                parentGroupId: child['id'] as int,
                title: child['name'] as String?,
              ),
            ),
          );
          if (mounted) _load();
        },
      ),
    );
  }

  Widget _buildGroupTab(dynamic group) {
    if (group['schedule_type'] == 'knockout') {
      // Rendered directly inline, like every other group format's tab — no
      // navigating away to a separate screen.
      return BracketView(
        leagueId: widget.leagueId,
        isHost: widget.isHost,
        format: _league?['format'] ?? 'singles',
        groupId: group['id'] as int,
        groupLocked: group['locked'] == true,
      );
    }

    final members = group['members'] as List;
    final schedule = _groupSchedules[group['id']] ?? [];
    final isMemberOfGroup = members.any((m) => m['id'] == _currentUserId);
    final hostEntersScores = _league?['host_enters_scores'] == true;
    final isCustom = group['schedule_type'] == 'custom';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Standings', style: Theme.of(context).textTheme.titleMedium),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _formatLabel(group),
                  style: const TextStyle(fontSize: 11, color: AppColors.accent, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._buildStandingsRows(members, group, isDark),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Schedule',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (widget.isHost && isCustom)
                TextButton.icon(
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    final added = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AddManualMatchScreen(
                          leagueId: widget.leagueId,
                          format: _league?['format'] ?? 'singles',
                          members: members,
                          groupId: group['id'] as int,
                        ),
                      ),
                    );
                    if (added == true) _load();
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Match'),
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
          if ((group['children'] as List?)?.isNotEmpty == true) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            Text('Combined Standings', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              'Across every group inside ${group['name']}',
              style: const TextStyle(fontSize: 11, color: AppColors.textGrey),
            ),
            const SizedBox(height: 8),
            ..._buildStandingsRows(
              (group['combinedMembers'] as List?) ?? [],
              group,
              isDark,
            ),
            const SizedBox(height: 20),
            Text('Groups inside', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...(group['children'] as List).map<Widget>(_buildChildGroupCard),
          ],
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
      final res = await ApiClient.put(
        '/leagues/${widget.leagueId}/schedule/${f['id']}',
        body: {
          'player1Id': result['player1Id'],
          'player2Id': result['player2Id'],
          'scheduledTime': result['scheduledTime'],
        },
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
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
            content: Text(res.errorOr('Could not update match.')),
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
      final res = await ApiClient.delete('/leagues/${widget.leagueId}/schedule/$scheduledMatchId');
      if (!mounted) return;
      if (res.statusCode == 200) {
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
            content: Text(res.errorOr('Could not remove match.')),
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
        player1Name: _teamLabel(f['player1_username'], f['player1_partner_username']),
        player2Name: _teamLabel(f['player2_username'], f['player2_partner_username']),
        title: 'Edit Score',
        unitLabel: _unitLabel,
        initialSets: initialSets,
      ),
    );
    if (result == null) return;

    HapticFeedback.lightImpact();
    try {
      final res = await ApiClient.put('/matches/${f['match_id']}/edit', body: result);
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res.data?['warning'] ?? 'Score updated and ratings recalculated.',
            ),
            backgroundColor: res.data?['warning'] != null
                ? AppColors.warning
                : AppColors.success,
          ),
        );
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not update score.')),
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
        player1Name: _teamLabel(f['player1_username'], f['player1_partner_username']),
        player2Name: _teamLabel(f['player2_username'], f['player2_partner_username']),
        title: 'Enter Score',
        unitLabel: _unitLabel,
      ),
    );
    if (result == null) return;

    HapticFeedback.lightImpact();
    try {
      final res = await ApiClient.post(
        '/matches/report-as-host',
        body: {
          'leagueId': widget.leagueId,
          'player1Id': f['player1_id'],
          'player1PartnerId': f['player1_partner_id'],
          'player2Id': f['player2_id'],
          'player2PartnerId': f['player2_partner_id'],
          'player1Units': result['player1Units'],
          'player2Units': result['player2Units'],
          'player1Won': result['player1Won'],
          'setScores': result['setScores'],
        },
      );
      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
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
            content: Text(res.errorOr('Could not enter score.')),
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
      final res = await ApiClient.delete('/matches/$matchId');
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.data?['warning'] ?? 'Match deleted.'),
            backgroundColor: res.data?['warning'] != null
                ? AppColors.warning
                : AppColors.success,
          ),
        );
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not delete match.')),
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
                        text: _teamLabel(f['player1_username'], f['player1_partner_username']),
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
                        text: _teamLabel(f['player2_username'], f['player2_partner_username']),
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
                  // Reassigning who's playing an unplayed fixture is
                  // singles-only for now — it only swaps individual
                  // player1Id/player2Id, with no way to pick a team, so
                  // offering it for a doubles group would silently drop
                  // partner assignments. Removing/re-adding the fixture is
                  // still available for doubles.
                  if (!_isDoubles)
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
}

class _SetScore {
  final TextEditingController myScore = TextEditingController();
  final TextEditingController opponentScore = TextEditingController();
}

class _HostScoreDialog extends StatefulWidget {
  final String player1Name;
  final String player2Name;
  final String title;
  final String unitLabel;
  final List<Map<String, int>>? initialSets;

  const _HostScoreDialog({
    required this.player1Name,
    required this.player2Name,
    this.title = 'Enter Score',
    this.unitLabel = 'Game',
    this.initialSets,
  });

  @override
  State<_HostScoreDialog> createState() => _HostScoreDialogState();
}

class _HostScoreDialogState extends State<_HostScoreDialog> {
  late List<_SetScore> _sets;
  String? _error;

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
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ),
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
                              '${widget.unitLabel} ${index + 1} — ${widget.player1Name}',
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
              label: Text('Add ${widget.unitLabel}'),
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
              if (p1 == null || p2 == null) {
                setState(() => _error = 'Please fill in every ${widget.unitLabel.toLowerCase()} score.');
                return;
              }
              if (p1 == p2) {
                setState(() => _error = 'A ${widget.unitLabel.toLowerCase()} cannot end in a tie.');
                return;
              }
              setScores.add({'me': p1, 'opponent': p2});
              totalP1 += p1;
              totalP2 += p2;
              if (p1 > p2) {
                setsWonByP1++;
              } else {
                setsWonByP2++;
              }
            }
            if (setsWonByP1 == setsWonByP2) {
              setState(() => _error = 'The match needs an overall winner.');
              return;
            }

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
  String? _error;

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
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ),
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
            if (_player1Id == null || _player2Id == null) {
              setState(() => _error = 'Please select both players.');
              return;
            }
            if (_player1Id == _player2Id) {
              setState(() => _error = 'The same player can\'t appear in both slots.');
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
