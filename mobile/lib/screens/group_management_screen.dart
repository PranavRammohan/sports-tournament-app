// group_management_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../api_client.dart';
import '../widgets/loading_skeleton.dart';

class GroupManagementScreen extends StatefulWidget {
  final int leagueId;

  const GroupManagementScreen({super.key, required this.leagueId});

  @override
  State<GroupManagementScreen> createState() => _GroupManagementScreenState();
}

class _GroupManagementScreenState extends State<GroupManagementScreen> {
  Map<String, dynamic>? _league;
  List<dynamic> _groups = [];
  List<dynamic> _unassignedMembers = [];
  bool _loading = true;
  String? _error;
  bool _submitting = false;

  bool get _isDoubles => _league?['format'] == 'doubles';

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

  Future<void> _createGroup() async {
    final nameController = TextEditingController();
    final matchesPerPlayerController = TextEditingController();
    final pointsWinController = TextEditingController(text: '2');
    final pointsLossController = TextEditingController(text: '0');
    String scheduleType = 'round_robin';
    bool overridePoints = false;
    bool overridePointsEnabled = true;

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
    final selectedSourceIds = <int>{..._groups.map<int>((g) => g['id'] as int)};

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
                ..._groups.map<Widget>((g) {
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
                          onPressed: (_submitting || _groups.length < 2)
                              ? null
                              : _autoAssign,
                          icon: const Icon(Icons.shuffle),
                          label: const Text('Auto-Assign'),
                        ),
                      ),
                    ],
                  ),
                  if (_groups.isNotEmpty) ...[
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

  // Which OTHER unlocked groups a given member could still be added to —
  // excludes groups they already belong to, since a player can be in
  // several groups at once and re-adding them somewhere they already are
  // would just be a no-op menu item.
  List<dynamic> _candidateGroupsFor(dynamic member, dynamic currentGroup) {
    return _groups.where((g) {
      if (g['id'] == currentGroup['id'] || g['locked'] == true) return false;
      final groupMembers = g['members'] as List;
      return !groupMembers.any((mm) => mm['id'] == member['id']);
    }).toList();
  }

  Widget _buildGroupCard(dynamic group) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final members = group['members'] as List;
    final units = _displayUnits(members);
    final locked = group['locked'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          group['name'],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
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
                    ],
                  ),
                ),
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
                if (!locked)
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: AppColors.danger,
                    ),
                    onPressed: _submitting
                        ? null
                        : () => _deleteGroup(group['id'], group['name']),
                  ),
              ],
            ),
            if (units.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _isDoubles ? 'No teams yet.' : 'No players yet.',
                  style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
                ),
              )
            else
              ...units.map<Widget>((m) {
                final candidateGroups = _candidateGroupsFor(m, group);
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${m['displayName']} (${m['rating']})',
                          style: const TextStyle(fontSize: 13),
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
    );
  }

  Widget _buildUnassignedRow(dynamic member) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unlockedGroups = _groups.where((g) => g['locked'] != true).toList();

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
            child: Text(
              '${member['displayName']} (${member['rating']})',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
