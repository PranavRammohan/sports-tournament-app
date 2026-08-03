// group_management_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../api_client.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/player_name.dart';

class GroupManagementScreen extends StatefulWidget {
  final int leagueId;

  const GroupManagementScreen({super.key, required this.leagueId});

  @override
  State<GroupManagementScreen> createState() => _GroupManagementScreenState();
}

class _GroupManagementScreenState extends State<GroupManagementScreen> {
  // Groups can nest inside other groups (see backend/leagueRoutes.js's
  // buildGroupTree). _groups holds the tree as returned by the API — root
  // nodes with a nested `children` list — and is what card rendering walks
  // recursively. _flatGroups is every group in the league at every depth,
  // flattened, and is what assignment/candidate/auto-assign/advance logic
  // uses — those operations apply to any group regardless of nesting.
  Map<String, dynamic>? _league;
  List<dynamic> _groups = [];
  List<dynamic> _flatGroups = [];
  List<dynamic> _unassignedMembers = [];
  bool _loading = true;
  String? _error;
  bool _submitting = false;

  // Sentinel distinguishing "user picked Top level" from "dialog dismissed
  // with no choice" in _moveGroup, since both would otherwise read as null.
  // Group ids are always positive (Postgres SERIAL), so -1 never collides.
  static const int _topLevelSentinel = -1;

  bool get _isDoubles => _league?['format'] == 'doubles';

  List<dynamic> _flattenGroups(List<dynamic> nodes) {
    final result = <dynamic>[];
    for (final node in nodes) {
      result.add(node);
      final children = node['children'] as List?;
      if (children != null && children.isNotEmpty) {
        result.addAll(_flattenGroups(children));
      }
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
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
        setState(() {
          _groups = groupsRes.data['groups'];
          _flatGroups = _flattenGroups(_groups);
          _unassignedMembers = groupsRes.data['unassignedMembers'];
        });
      } else {
        setState(() => _error = groupsRes.errorOr('Could not load groups.'));
      }
    } catch (err) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Doubles: a group's member list carries both partners of a team as
  // separate entries (always sharing identical group_ids/stats — see the
  // backend's getGroupsWithStandings), since a player can be in several
  // groups independently of their partner's own membership history. This
  // collapses that down to one display row per team for Manage Groups,
  // where the pair is always assigned/unassigned/moved as a single unit.
  // Singles leagues get one entry per player, unchanged, just with a
  // displayName added so rendering code can stay uniform.
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
        'displayName': partner != null
            ? '${m['username']} & ${partner['username']}'
            : m['username'],
      });
    }
    return units;
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

  // Shared by the create-group dialog and the advance-to-new-group dialog —
  // both need "pick a format for this group" with the same four options.
  Widget _scheduleTypeRadios({
    required String value,
    required ValueChanged<String> onChanged,
    required TextEditingController matchesPerPlayerController,
  }) {
    return RadioGroup<String>(
      groupValue: value,
      onChanged: (v) => onChanged(v!),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: 'round_robin',
            title: const Text('Round Robin', style: TextStyle(fontSize: 13)),
          ),
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: 'matches_per_player',
            title: const Text(
              'Fixed matches per player',
              style: TextStyle(fontSize: 13),
            ),
          ),
          if (value == 'matches_per_player')
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
              child: TextField(
                controller: matchesPerPlayerController,
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
            dense: true,
            value: 'knockout',
            title: const Text('Knockout', style: TextStyle(fontSize: 13)),
            subtitle: const Text(
              'Needs an exact power-of-2 number of players',
              style: TextStyle(fontSize: 11),
            ),
          ),
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: 'custom',
            title: const Text(
              'Custom — I\'ll add matches myself',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // Shared by the create-group dialog and the edit-format dialog — lets a
  // group inherit the tournament's points config (the default, no override
  // stored) or set its own win/loss point values. Hidden for knockout groups,
  // which never award league points regardless of config (bracket matches
  // don't call the points-resolution logic at all — see matchRoutes.js).
  Widget _pointsOverrideSection({
    required String scheduleType,
    required bool overridePoints,
    required bool pointsEnabled,
    required ValueChanged<bool> onOverrideChanged,
    required ValueChanged<bool> onPointsEnabledChanged,
    required TextEditingController pointsWinController,
    required TextEditingController pointsLossController,
  }) {
    if (scheduleType == 'knockout') return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: overridePoints,
          onChanged: onOverrideChanged,
          title: const Text(
            'Override tournament points for this group',
            style: TextStyle(fontSize: 13),
          ),
        ),
        if (overridePoints) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: pointsEnabled,
            onChanged: onPointsEnabledChanged,
            title: const Text(
              'Award points in this group',
              style: TextStyle(fontSize: 13),
            ),
          ),
          if (pointsEnabled)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: pointsWinController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Points for a win',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: pointsLossController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Points for a loss',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ],
    );
  }

  // `initialParentId` pre-selects "Create inside" (used by a group card's
  // "Add group inside" action); left null for the screen-level "New Group"
  // button, which defaults to top level.
  Future<void> _createGroup({int? initialParentId}) async {
    final nameController = TextEditingController();
    final matchesPerPlayerController = TextEditingController();
    final pointsWinController = TextEditingController(text: '2');
    final pointsLossController = TextEditingController(text: '0');
    String scheduleType = 'round_robin';
    bool overridePoints = false;
    bool overridePointsEnabled = true;
    int? parentGroupId = initialParentId;
    // Only a group with no players of its own can accept a nested group —
    // mirrors the backend's "parent must be empty" rule in POST /groups.
    final eligibleParents = _flatGroups.where((g) => (g['members'] as List).isEmpty).toList();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          title: const Text('New Group'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Group name',
                    hintText: 'e.g. Group A',
                  ),
                ),
                const SizedBox(height: 12),
                if (eligibleParents.isNotEmpty) ...[
                  DropdownButtonFormField<int?>(
                    initialValue: parentGroupId,
                    decoration: const InputDecoration(
                      labelText: 'Create inside',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Top level'),
                      ),
                      ...eligibleParents.map(
                        (g) => DropdownMenuItem<int?>(
                          value: g['id'] as int,
                          child: Text(
                            g['name'],
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) => setDialogState(() => parentGroupId = v),
                  ),
                  const SizedBox(height: 12),
                ],
                Text('Format', style: Theme.of(ctx).textTheme.titleSmall),
                _scheduleTypeRadios(
                  value: scheduleType,
                  onChanged: (v) => setDialogState(() => scheduleType = v),
                  matchesPerPlayerController: matchesPerPlayerController,
                ),
                _pointsOverrideSection(
                  scheduleType: scheduleType,
                  overridePoints: overridePoints,
                  pointsEnabled: overridePointsEnabled,
                  onOverrideChanged: (v) => setDialogState(() => overridePoints = v),
                  onPointsEnabledChanged: (v) => setDialogState(() => overridePointsEnabled = v),
                  pointsWinController: pointsWinController,
                  pointsLossController: pointsLossController,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                int? matchesPerPlayer;
                if (scheduleType == 'matches_per_player') {
                  matchesPerPlayer = int.tryParse(matchesPerPlayerController.text.trim());
                  if (matchesPerPlayer == null || matchesPerPlayer < 1) return;
                }
                final body = <String, dynamic>{
                  'name': name,
                  'scheduleType': scheduleType,
                  'matchesPerPlayer': matchesPerPlayer,
                  'parentGroupId': parentGroupId,
                };
                if (overridePoints && scheduleType != 'knockout') {
                  body['pointsEnabled'] = overridePointsEnabled;
                  if (overridePointsEnabled) {
                    final pointsWin = int.tryParse(pointsWinController.text.trim());
                    final pointsLoss = int.tryParse(pointsLossController.text.trim());
                    if (pointsWin == null || pointsWin < 0 || pointsLoss == null || pointsLoss < 0) return;
                    body['pointsWin'] = pointsWin;
                    body['pointsLoss'] = pointsLoss;
                  }
                }
                Navigator.pop(ctx, body);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;

    HapticFeedback.lightImpact();
    setState(() => _submitting = true);
    try {
      final res = await ApiClient.post(
        '/leagues/${widget.leagueId}/groups',
        body: result,
      );
      if (!mounted) return;
      if (res.statusCode == 201) {
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not create group.')),
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
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _editGroupFormat(dynamic group) async {
    final matchesPerPlayerController = TextEditingController(
      text: group['matches_per_player'] != null ? '${group['matches_per_player']}' : '',
    );
    String scheduleType = group['schedule_type'] ?? 'round_robin';

    final hasPointsOverride = group['points_enabled'] != null ||
        group['points_win'] != null ||
        group['points_loss'] != null;
    bool overridePoints = hasPointsOverride;
    bool overridePointsEnabled = group['points_enabled'] ?? true;
    final pointsWinController = TextEditingController(
      text: (group['points_win'] ?? 2).toString(),
    );
    final pointsLossController = TextEditingController(
      text: (group['points_loss'] ?? 0).toString(),
    );

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          title: Text('Edit Format — ${group['name']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _scheduleTypeRadios(
                  value: scheduleType,
                  onChanged: (v) => setDialogState(() => scheduleType = v),
                  matchesPerPlayerController: matchesPerPlayerController,
                ),
                _pointsOverrideSection(
                  scheduleType: scheduleType,
                  overridePoints: overridePoints,
                  pointsEnabled: overridePointsEnabled,
                  onOverrideChanged: (v) => setDialogState(() => overridePoints = v),
                  onPointsEnabledChanged: (v) => setDialogState(() => overridePointsEnabled = v),
                  pointsWinController: pointsWinController,
                  pointsLossController: pointsLossController,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                int? matchesPerPlayer;
                if (scheduleType == 'matches_per_player') {
                  matchesPerPlayer = int.tryParse(matchesPerPlayerController.text.trim());
                  if (matchesPerPlayer == null || matchesPerPlayer < 1) return;
                }
                final body = <String, dynamic>{
                  'scheduleType': scheduleType,
                  'matchesPerPlayer': matchesPerPlayer,
                };
                if (overridePoints && scheduleType != 'knockout') {
                  body['pointsEnabled'] = overridePointsEnabled;
                  if (overridePointsEnabled) {
                    final pointsWin = int.tryParse(pointsWinController.text.trim());
                    final pointsLoss = int.tryParse(pointsLossController.text.trim());
                    if (pointsWin == null || pointsWin < 0 || pointsLoss == null || pointsLoss < 0) return;
                    body['pointsWin'] = pointsWin;
                    body['pointsLoss'] = pointsLoss;
                  }
                }
                Navigator.pop(ctx, body);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;

    HapticFeedback.lightImpact();
    setState(() => _submitting = true);
    try {
      final res = await ApiClient.put(
        '/leagues/${widget.leagueId}/groups/${group['id']}/config',
        body: result,
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not update this group\'s format.')),
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
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _deleteGroup(int groupId, String groupName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text('Delete "$groupName"?'),
        content: const Text(
          'Any players in this group will become unassigned.',
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
    setState(() => _submitting = true);
    try {
      final res = await ApiClient.delete('/leagues/${widget.leagueId}/groups/$groupId');
      if (!mounted) return;
      if (res.statusCode == 200) {
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not delete group.')),
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
      if (mounted) setState(() => _submitting = false);
    }
  }

  // Groups this group could validly move under — excludes itself and any of
  // its own descendants (moving a group inside its own subtree is nonsense
  // and the server rejects it too), and any group that already has players
  // of its own (same "parent must be empty" rule as creating a group
  // inside one — see POST /:id/groups). Filtering client-side avoids
  // offering an option that will just fail.
  List<dynamic> _validMoveTargets(dynamic group) {
    final descendantIds = <int>{};
    void collect(dynamic node) {
      for (final child in (node['children'] as List? ?? [])) {
        descendantIds.add(child['id'] as int);
        collect(child);
      }
    }
    collect(group);
    return _flatGroups
        .where((g) =>
            g['id'] != group['id'] &&
            !descendantIds.contains(g['id']) &&
            (g['members'] as List).isEmpty)
        .toList();
  }

  // Purely organizational — moving a group never touches its own roster/
  // fixtures or its children's (see PATCH .../parent in leagueRoutes.js).
  Future<void> _moveGroup(dynamic group) async {
    final targets = _validMoveTargets(group);
    final choice = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Move "${group['name']}" to...'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, _topLevelSentinel),
            child: const Text('Top level'),
          ),
          ...targets.map(
            (g) => SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, g['id'] as int),
              child: Text(g['name']),
            ),
          ),
        ],
      ),
    );
    if (choice == null) return;

    HapticFeedback.lightImpact();
    setState(() => _submitting = true);
    try {
      final res = await ApiClient.patch(
        '/leagues/${widget.leagueId}/groups/${group['id']}/parent',
        body: {'parentGroupId': choice == _topLevelSentinel ? null : choice},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not move this group.')),
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
      if (mounted) setState(() => _submitting = false);
    }
  }

  // Purely additive — a player can belong to any number of groups. Adding
  // them to another group never removes them from groups they're already
  // in, so there's nothing destructive here worth confirming.
  Future<void> _assignToGroup(int userId, int groupId) async {
    HapticFeedback.selectionClick();
    setState(() => _submitting = true);
    try {
      final res = await ApiClient.post(
        '/leagues/${widget.leagueId}/groups/$groupId/assign',
        body: {'userId': userId},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not add this player.')),
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
      if (mounted) setState(() => _submitting = false);
    }
  }

  // Removes a player from THIS one group only — undoing a mis-click before
  // it matters. Never touches any other group they belong to.
  Future<void> _unassign(int userId, int groupId) async {
    HapticFeedback.selectionClick();
    setState(() => _submitting = true);
    try {
      final res = await ApiClient.post(
        '/leagues/${widget.leagueId}/groups/$groupId/unassign',
        body: {'userId': userId},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not remove this player.')),
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
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _autoAssign() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('Auto-assign everyone?'),
        content: const Text(
          'This distributes players who aren\'t in any group yet across the unlocked groups by rating (highest rated to the first group, next to the second, and so on, cycling through). Anyone already placed in a group — locked or not — is left exactly where they are.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Auto-Assign'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    HapticFeedback.mediumImpact();
    setState(() => _submitting = true);
    try {
      final res = await ApiClient.post('/leagues/${widget.leagueId}/groups/auto-assign');
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Players auto-assigned.'),
            backgroundColor: AppColors.success,
          ),
        );
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not auto-assign.')),
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
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _lockGroup(int groupId, String groupName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text('Lock "$groupName" and generate its matches?'),
        content: const Text(
          'This freezes this group\'s membership and generates its schedule (or bracket, for knockout) in its own format. Other groups are unaffected — you can unlock this one later if you need to make changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Lock & Start',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    HapticFeedback.mediumImpact();
    setState(() => _submitting = true);
    try {
      final res = await ApiClient.post('/leagues/${widget.leagueId}/groups/$groupId/lock');
      if (!mounted) return;
      if (res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.data?['message'] ?? 'Group locked.'),
            backgroundColor: AppColors.success,
          ),
        );
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not lock this group.')),
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
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _unlockGroup(int groupId, String groupName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text('Unlock "$groupName"?'),
        content: const Text(
          'This reverses every confirmed match in this group — all results, rating changes, and points earned — and wipes its schedule/bracket entirely, so you can edit it and re-lock when ready. Other groups are untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Unlock & Wipe',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    HapticFeedback.mediumImpact();
    setState(() => _submitting = true);
    try {
      final res = await ApiClient.post('/leagues/${widget.leagueId}/groups/$groupId/unlock');
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.data?['message'] ?? 'Group unlocked.'),
            backgroundColor: AppColors.success,
          ),
        );
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not unlock this group.')),
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
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _advanceToNewGroup() async {
    final nameController = TextEditingController(text: 'Next Round');
    final advanceCountController = TextEditingController(text: '2');
    final matchesPerPlayerController = TextEditingController();
    String scheduleType = 'knockout';
    // A group with sub-groups never has players of its own to advance from
    // (see the assign-route restriction) — only offer childless groups.
    final eligibleSourceGroups = _flatGroups
        .where((g) => ((g['children'] as List?) ?? []).isEmpty)
        .toList();
    final selectedSourceIds = <int>{...eligibleSourceGroups.map<int>((g) => g['id'] as int)};

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          title: const Text('Advance Top Players to a New Group'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'New group name',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Text('From which groups?', style: Theme.of(ctx).textTheme.titleSmall),
                ...eligibleSourceGroups.map<Widget>((g) {
                  final id = g['id'] as int;
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: selectedSourceIds.contains(id),
                    title: Text(g['name'], style: const TextStyle(fontSize: 13)),
                    onChanged: (checked) => setDialogState(() {
                      if (checked == true) {
                        selectedSourceIds.add(id);
                      } else {
                        selectedSourceIds.remove(id);
                      }
                    }),
                  );
                }),
                const SizedBox(height: 8),
                TextField(
                  controller: advanceCountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _isDoubles
                        ? 'Teams advancing per source group'
                        : 'Players advancing per source group',
                    isDense: true,
                    hintText: 'e.g. 2',
                  ),
                ),
                const SizedBox(height: 12),
                Text('New group\'s format', style: Theme.of(ctx).textTheme.titleSmall),
                _scheduleTypeRadios(
                  value: scheduleType,
                  onChanged: (v) => setDialogState(() => scheduleType = v),
                  matchesPerPlayerController: matchesPerPlayerController,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedSourceIds.isEmpty) return;
                final advanceCount = int.tryParse(advanceCountController.text.trim());
                if (advanceCount == null || advanceCount < 1) return;
                int? matchesPerPlayer;
                if (scheduleType == 'matches_per_player') {
                  matchesPerPlayer = int.tryParse(matchesPerPlayerController.text.trim());
                  if (matchesPerPlayer == null || matchesPerPlayer < 1) return;
                }
                Navigator.pop(ctx, {
                  'name': nameController.text.trim(),
                  'sourceGroupIds': selectedSourceIds.toList(),
                  'advanceCount': advanceCount,
                  'scheduleType': scheduleType,
                  'matchesPerPlayer': matchesPerPlayer,
                });
              },
              child: const Text('Create Group'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;

    await _submitAdvance(result);
  }

  Future<void> _submitAdvance(Map<String, dynamic> body, {bool force = false}) async {
    HapticFeedback.lightImpact();
    setState(() => _submitting = true);
    try {
      final res = await ApiClient.post(
        '/leagues/${widget.leagueId}/groups/advance',
        body: {...body, 'force': force},
      );
      if (!mounted) return;
      if (res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.data?['message'] ?? 'New group created.'),
            backgroundColor: AppColors.success,
          ),
        );
        await _load();
      } else if (res.data is Map && res.data['incompleteMatches'] != null) {
        setState(() => _submitting = false);
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            title: const Text('Group play not finished yet'),
            content: Text('${res.data['error']} Create the new group anyway?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Create Anyway'),
              ),
            ],
          ),
        );
        if (proceed == true) {
          await _submitAdvance(body, force: true);
        }
        return;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not create the new group.')),
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
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Groups')),
      body: _loading
          ? const SkeletonList()
          : _error != null
          ? Center(
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
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _submitting ? null : _createGroup,
                          icon: const Icon(Icons.add),
                          label: const Text('New Group'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          // Auto-assign only ever targets unlocked, childless
                          // groups (a group with sub-groups can't hold
                          // players directly) — mirrors the backend's own
                          // "at least 2 unlocked, playable groups" check.
                          onPressed: (_submitting ||
                                  _flatGroups
                                          .where((g) =>
                                              g['locked'] != true &&
                                              ((g['children'] as List?) ?? []).isEmpty)
                                          .length <
                                      2)
                              ? null
                              : _autoAssign,
                          icon: const Icon(Icons.shuffle),
                          label: const Text('Auto-Assign'),
                        ),
                      ),
                    ],
                  ),
                  if (_flatGroups.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _submitting ? null : _advanceToNewGroup,
                      icon: const Icon(Icons.arrow_upward),
                      label: const Text('Advance Top Players to a New Group'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ..._groups.map((g) => _buildGroupCard(g)),
                  if (_unassignedMembers.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _isDoubles ? 'Unassigned Teams' : 'Unassigned Players',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ..._displayUnits(_unassignedMembers).map((m) => _buildUnassignedRow(m)),
                  ],
                ],
              ),
            ),
    );
  }

  // Which OTHER unlocked, playable (childless) groups a given member could
  // still be added to — excludes groups they already belong to (a player
  // can be in several groups at once, re-adding them somewhere they already
  // are would be a no-op) and any group with sub-groups, since the backend
  // only accepts players directly into a group that has none.
  List<dynamic> _candidateGroupsFor(dynamic member, dynamic currentGroup) {
    return _flatGroups.where((g) {
      if (g['id'] == currentGroup['id'] || g['locked'] == true) return false;
      if (((g['children'] as List?) ?? []).isNotEmpty) return false;
      final groupMembers = g['members'] as List;
      return !groupMembers.any((mm) => mm['id'] == member['id']);
    }).toList();
  }

  // `depth` indents nested groups under their parent and is how the tree
  // reads visually — the card itself always keeps its full control set
  // (assign/lock/edit/delete) regardless of nesting, since a group stays
  // fully playable whether or not it has a parent or children.
  Widget _buildGroupCard(dynamic group, {int depth = 0}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final members = group['members'] as List;
    final units = _displayUnits(members);
    final locked = group['locked'] == true;
    final children = (group['children'] as List?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 20.0 * depth, bottom: 12),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.cardBorder(isDark)),
              boxShadow: AppShadows.card(isDark),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Text(
                              group['name'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            // A group with sub-groups is purely organizational —
                            // its format/lock state never applies (the backend
                            // refuses to assign players or lock it directly once
                            // it has children), so that badge would just be noise.
                            if (children.isEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _formatLabel(group),
                                  style: const TextStyle(fontSize: 10, color: AppColors.accent, fontWeight: FontWeight.w600),
                                ),
                              ),
                            if (children.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${children.length} inside',
                                  style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (children.isEmpty) ...[
                        Text(
                          _isDoubles
                              ? '${units.length} team${units.length == 1 ? '' : 's'}'
                              : '${units.length} player${units.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textGrey,
                          ),
                        ),
                        if (!locked)
                          IconButton(
                            icon: const Icon(Icons.tune, size: 18),
                            tooltip: 'Edit format',
                            onPressed: _submitting ? null : () => _editGroupFormat(group),
                          ),
                        IconButton(
                          icon: Icon(
                            locked ? Icons.lock_open_outlined : Icons.lock_outline,
                            size: 18,
                            color: locked ? AppColors.danger : AppColors.success,
                          ),
                          tooltip: locked ? 'Unlock group' : 'Lock group & generate matches',
                          onPressed: _submitting
                              ? null
                              : () => locked
                                  ? _unlockGroup(group['id'], group['name'])
                                  : _lockGroup(group['id'], group['name']),
                        ),
                      ],
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 18),
                        enabled: !_submitting,
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                            value: 'add_inside',
                            child: Text('Add group inside'),
                          ),
                          const PopupMenuItem(
                            value: 'move',
                            child: Text('Move to...'),
                          ),
                          if (!locked)
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text(
                                'Delete',
                                style: TextStyle(color: AppColors.danger),
                              ),
                            ),
                        ],
                        onSelected: (action) {
                          switch (action) {
                            case 'add_inside':
                              _createGroup(initialParentId: group['id'] as int);
                              break;
                            case 'move':
                              _moveGroup(group);
                              break;
                            case 'delete':
                              _deleteGroup(group['id'], group['name']);
                              break;
                          }
                        },
                      ),
                    ],
                  ),
                  // A group with sub-groups never has a roster of its own —
                  // players belong in the sub-groups (enforced by the backend
                  // assign route) — so skip the roster section entirely.
                  if (children.isEmpty && units.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _isDoubles ? 'No teams yet.' : 'No players yet.',
                        style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
                      ),
                    )
                  else if (children.isEmpty)
                    ...units.map<Widget>((m) {
                      final candidateGroups = _candidateGroupsFor(m, group);
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: _isDoubles
                                  ? Text(
                                      '${m['displayName']} (${m['rating']})',
                                      style: const TextStyle(fontSize: 13),
                                    )
                                  : Row(
                                      children: [
                                        Flexible(
                                          child: PlayerName(
                                            userId: m['id'] as int?,
                                            name: m['displayName'] ?? '',
                                            isGuest: m['is_guest'] == true,
                                            style: const TextStyle(fontSize: 13),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          ' (${m['rating']})',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ],
                                    ),
                            ),
                            if (candidateGroups.isNotEmpty)
                              PopupMenuButton<int>(
                                icon: const Icon(Icons.group_add_outlined, size: 16),
                                tooltip: 'Add to another group',
                                enabled: !_submitting,
                                itemBuilder: (ctx) => candidateGroups
                                    .map<PopupMenuItem<int>>(
                                      (g) => PopupMenuItem(
                                        value: g['id'] as int,
                                        child: Text('Add to ${g['name']}'),
                                      ),
                                    )
                                    .toList(),
                                onSelected: (targetGroupId) => _assignToGroup(m['id'], targetGroupId),
                              ),
                            if (!locked)
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                tooltip: 'Remove from this group',
                                onPressed: _submitting
                                    ? null
                                    : () => _unassign(m['id'], group['id']),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ),
        ...children.map<Widget>((child) => _buildGroupCard(child, depth: depth + 1)),
      ],
    );
  }

  Widget _buildUnassignedRow(dynamic member) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Only unlocked, childless groups accept players directly — a group
    // with sub-groups is a container (see _candidateGroupsFor above).
    final unlockedGroups = _flatGroups
        .where((g) => g['locked'] != true && ((g['children'] as List?) ?? []).isEmpty)
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder(isDark)),
        boxShadow: AppShadows.card(isDark),
      ),
      child: Row(
        children: [
          Expanded(
            child: _isDoubles
                ? Text(
                    '${member['displayName']} (${member['rating']})',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  )
                : Row(
                    children: [
                      Flexible(
                        child: PlayerName(
                          userId: member['id'] as int?,
                          name: member['displayName'] ?? '',
                          isGuest: member['is_guest'] == true,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        ' (${member['rating']})',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ],
                  ),
          ),
          DropdownButton<int>(
            hint: const Text('Assign to...', style: TextStyle(fontSize: 12)),
            underline: const SizedBox(),
            items: unlockedGroups
                .map<DropdownMenuItem<int>>(
                  (g) => DropdownMenuItem(
                    value: g['id'] as int,
                    child: Text(
                      g['name'],
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                )
                .toList(),
            onChanged: _submitting
                ? null
                : (groupId) {
                    if (groupId != null) {
                      _assignToGroup(member['id'], groupId);
                    }
                  },
          ),
        ],
      ),
    );
  }
}
