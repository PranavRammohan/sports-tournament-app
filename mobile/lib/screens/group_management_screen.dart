// group_management_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../api_client.dart';

class GroupManagementScreen extends StatefulWidget {
  final int leagueId;

  const GroupManagementScreen({super.key, required this.leagueId});

  @override
  State<GroupManagementScreen> createState() => _GroupManagementScreenState();
}

class _GroupManagementScreenState extends State<GroupManagementScreen> {
  List<dynamic> _groups = [];
  List<dynamic> _unassignedMembers = [];
  bool _loading = true;
  String? _error;
  bool _submitting = false;

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
      final res = await ApiClient.get('/leagues/${widget.leagueId}/groups');
      if (res.statusCode == 200) {
        setState(() {
          _groups = res.data['groups'];
          _unassignedMembers = res.data['unassignedMembers'];
        });
      } else {
        setState(() => _error = res.errorOr('Could not load groups.'));
      }
    } catch (err) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
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

  // Shared by the create-group dialog and the advance-to-new-group dialog —
  // both need "pick a format for this group" with the same four options.
  Widget _scheduleTypeRadios({
    required String value,
    required ValueChanged<String> onChanged,
    required TextEditingController matchesPerPlayerController,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: 'round_robin',
          groupValue: value,
          title: const Text('Round Robin', style: TextStyle(fontSize: 13)),
          onChanged: (v) => onChanged(v!),
        ),
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: 'matches_per_player',
          groupValue: value,
          title: const Text('Fixed matches per player', style: TextStyle(fontSize: 13)),
          onChanged: (v) => onChanged(v!),
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
          groupValue: value,
          title: const Text('Knockout', style: TextStyle(fontSize: 13)),
          subtitle: const Text(
            'Needs an exact power-of-2 number of players',
            style: TextStyle(fontSize: 11),
          ),
          onChanged: (v) => onChanged(v!),
        ),
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: 'custom',
          groupValue: value,
          title: const Text('Custom — I\'ll add matches myself', style: TextStyle(fontSize: 13)),
          onChanged: (v) => onChanged(v!),
        ),
      ],
    );
  }

  Future<void> _createGroup() async {
    final nameController = TextEditingController();
    final matchesPerPlayerController = TextEditingController();
    String scheduleType = 'round_robin';

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
                Navigator.pop(ctx, {
                  'name': name,
                  'scheduleType': scheduleType,
                  'matchesPerPlayer': matchesPerPlayer,
                });
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

  Future<void> _assignToGroup(int userId, int groupId, {String? fromGroupName, required String toGroupName}) async {
    if (fromGroupName != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          title: Text('Move to "$toGroupName"?'),
          content: Text(
            'This removes their unplayed matches in "$fromGroupName" — confirmed results and rating changes stay as-is.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Move'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

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
            content: Text(res.errorOr('Could not assign player.')),
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

  Future<void> _unassign(int userId) async {
    HapticFeedback.selectionClick();
    setState(() => _submitting = true);
    try {
      final res = await ApiClient.post(
        '/leagues/${widget.leagueId}/groups/unassign',
        body: {'userId': userId},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not unassign player.')),
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
          'This distributes players across the unlocked groups by rating (highest rated to the first group, next to the second, and so on, cycling through), overwriting assignments already made in those groups. Locked groups and their members are left untouched.',
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
                  decoration: const InputDecoration(
                    labelText: 'Players advancing per source group',
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
          ? const Center(child: CircularProgressIndicator())
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
                      'Unassigned Players',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ..._unassignedMembers.map((m) => _buildUnassignedRow(m)),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildGroupCard(dynamic group) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final members = group['members'] as List;
    final locked = group['locked'] == true;
    final otherUnlockedGroups = _groups.where(
      (g) => g['id'] != group['id'] && g['locked'] != true,
    ).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
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
                  '${members.length} player${members.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGrey,
                  ),
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
            if (members.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'No players yet.',
                  style: TextStyle(fontSize: 12, color: AppColors.textGrey),
                ),
              )
            else
              ...members.map<Widget>((m) {
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${m['username']} (${m['rating']})',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      if (otherUnlockedGroups.isNotEmpty)
                        PopupMenuButton<int>(
                          icon: const Icon(Icons.swap_horiz, size: 16),
                          tooltip: 'Move to another group',
                          enabled: !_submitting,
                          itemBuilder: (ctx) => otherUnlockedGroups
                              .map<PopupMenuItem<int>>(
                                (g) => PopupMenuItem(
                                  value: g['id'] as int,
                                  child: Text('Move to ${g['name']}'),
                                ),
                              )
                              .toList(),
                          onSelected: (targetGroupId) => _assignToGroup(
                            m['id'],
                            targetGroupId,
                            fromGroupName: group['name'],
                            toGroupName: otherUnlockedGroups
                                .firstWhere((g) => g['id'] == targetGroupId)['name'],
                          ),
                        ),
                      if (!locked)
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          tooltip: 'Unassign',
                          onPressed: _submitting
                              ? null
                              : () => _unassign(m['id']),
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
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: AppShadows.card(isDark),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${member['username']} (${member['rating']})',
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
                      final targetName = unlockedGroups.firstWhere((g) => g['id'] == groupId)['name'];
                      _assignToGroup(member['id'], groupId, toGroupName: targetName);
                    }
                  },
          ),
        ],
      ),
    );
  }
}
