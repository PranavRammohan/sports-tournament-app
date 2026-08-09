// league_detail_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../main.dart';
import '../api_client.dart';
import '../utils.dart';
import '../date_utils.dart';
import '../widgets/sport_icon.dart';
import '../widgets/player_avatar.dart';
import '../widgets/match_badges.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/friendly_empty_state.dart';
import '../widgets/match_photo_thumbnail.dart';
import '../widgets/match_photo_picker.dart';
import '../widgets/team_name_row.dart';
import 'report_match_screen.dart';
import 'playoffs_screen.dart';
import 'regenerate_schedule_dialog.dart';
import 'add_players_screen.dart';
import 'add_manual_match_screen.dart';
import 'edit_league_screen.dart';
import 'group_management_screen.dart';
import 'groups_overview_screen.dart';
import 'player_profile_screen.dart';
import 'partner_selection_screen.dart';
import 'audit_log_screen.dart';

class LeagueDetailScreen extends StatefulWidget {
  final int leagueId;

  const LeagueDetailScreen({super.key, required this.leagueId});

  @override
  State<LeagueDetailScreen> createState() => _LeagueDetailScreenState();
}

class _LeagueDetailScreenState extends State<LeagueDetailScreen> {
  Map<String, dynamic>? _league;
  List<dynamic> _leaderboard = [];
  List<dynamic>? _pairLeaderboard;
  bool _showPairs = true;
  List<dynamic> _schedule = [];
  List<dynamic> _bracket = [];
  List<dynamic> _announcements = [];
  int? _currentUserId;
  bool _loading = true;
  bool _deleting = false;
  bool _leaving = false;
  bool _completing = false;
  bool _joining = false;
  bool _generating = false;
  bool _regenerating = false;
  String? _error;

  bool get _isMember =>
      _currentUserId != null &&
      _leaderboard.any((p) => p['id'] == _currentUserId);
  // The narrower "is this the original creator" check — used only for the
  // handful of actions co-hosts still can't do (delete league, manage
  // co-hosts). Everything else in this app should use the widened `isHost`
  // computed in build() instead.
  bool get _isPrimaryHost =>
      _league != null && _league!['created_by'] == _currentUserId;
  bool get _isKnockout =>
      _league != null && _league!['schedule_type'] == 'knockout';
  bool get _isCustom =>
      _league != null && _league!['schedule_type'] == 'custom';
  bool get _isLeagueStyle => !_isKnockout && !_isCustom;
  bool get _isDoublesLeague =>
      _league != null && _league!['format'] == 'doubles';
  String get _partnerMode =>
      _league != null ? (_league!['partner_mode'] ?? 'host_auto') : 'host_auto';
  bool get _isCompleted => _league != null && _league!['status'] == 'completed';
  bool get _pointsEnabled =>
      _league == null || _league!['points_enabled'] != false;
  String get _pointsSubtitle {
    if (!_pointsEnabled) return 'Ranked by wins, then rating';
    final win = _league?['points_win'] ?? 2;
    final loss = _league?['points_loss'] ?? 0;
    return 'Ranked by tournament points (win = $win pts, loss = $loss)';
  }
  bool get _hasConfirmedMatches {
    if (_isKnockout) {
      return _bracket.any((m) => m['status'] == 'confirmed');
    }
    return _schedule.any((f) => f['match_status'] == 'confirmed');
  }

  // Tennis is scored in "Sets"; everything else in this app (badminton,
  // table tennis, pickleball) is scored in "Games" — used to label the
  // report/edit-score dialogs correctly per sport.
  String get _unitLabel =>
      (_league != null && _league!['sport'] == 'tennis') ? 'Set' : 'Game';

  // Returns a user-facing message if joining is currently blocked by the
  // league's optional registration window, or null if joining is allowed
  // (which is always the case when the host hasn't set a window at all).
  String? get _registrationMessage {
    if (_league == null) return null;
    final startRaw = _league!['registration_start'];
    final endRaw = _league!['registration_end'];
    if (startRaw == null && endRaw == null) return null;

    final now = DateTime.now();
    if (startRaw != null) {
      final start = DateTime.tryParse(startRaw.toString())?.toLocal();
      if (start != null && now.isBefore(start)) {
        return 'Registration opens ${_formatRegistrationDate(start)}.';
      }
    }
    if (endRaw != null) {
      final end = DateTime.tryParse(endRaw.toString())?.toLocal();
      if (end != null && now.isAfter(end)) {
        return 'Registration closed ${_formatRegistrationDate(end)}.';
      }
    }
    return null;
  }

  String _formatRegistrationDate(DateTime dt) {
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
    return 'on ${months[dt.month - 1]} ${dt.day} at $hour12:$minute $ampm';
  }

  @override
  void initState() {
    super.initState();
    _loadAll(showFullLoading: true);
  }

  Future<void> _loadAll({bool showFullLoading = false}) async {
    setState(() {
      if (showFullLoading) _loading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('user');
      if (userJson != null) {
        _currentUserId = jsonDecode(userJson)['id'];
      }

      final leagueRes = await ApiClient.get('/leagues/${widget.leagueId}');
      if (leagueRes.statusCode != 200) {
        setState(
          () => _error = leagueRes.errorOr('Could not load tournament.'),
        );
        return;
      }
      setState(() {
        _league = leagueRes.data['league'];
        _leaderboard = leagueRes.data['leaderboard'];
        _pairLeaderboard = leagueRes.data['pairLeaderboard'];
      });

      if (_isKnockout) {
        final bracketRes = await ApiClient.get('/playoffs/${widget.leagueId}');
        if (bracketRes.statusCode == 200) {
          setState(() => _bracket = bracketRes.data['bracket']);
        }
      } else {
        final scheduleRes = await ApiClient.get(
          '/leagues/${widget.leagueId}/schedule',
        );
        if (scheduleRes.statusCode == 200) {
          setState(() => _schedule = scheduleRes.data['schedule']);
        }
      }

      final announcementsRes = await ApiClient.get(
        '/leagues/${widget.leagueId}/announcements',
      );
      if (announcementsRes.statusCode == 200) {
        setState(() => _announcements = announcementsRes.data['announcements']);
      }
    } catch (err) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (showFullLoading) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _joinLeague() async {
    HapticFeedback.lightImpact();
    setState(() => _joining = true);
    try {
      final res = await ApiClient.post('/leagues/${widget.leagueId}/join');

      if (!mounted) return;
      if (res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Joined tournament!'),
            backgroundColor: AppColors.success,
          ),
        );
        await _loadAll();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not join.')),
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

  Future<void> _generateSchedule({bool force = false}) async {
    HapticFeedback.lightImpact();
    setState(() => _generating = true);
    try {
      final res = await ApiClient.post(
        '/leagues/${widget.leagueId}/generate-schedule',
        body: {'force': force},
      );

      if (!mounted) return;
      if (res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.data?['message'] ?? 'Schedule generated.'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadAll();
      } else if (res.data is Map && res.data['estimatedMatches'] != null) {
        setState(() => _generating = false);
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            title: const Text('That\'s a lot of matches'),
            content: Text('${res.data['error']} Continue anyway?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Generate Anyway'),
              ),
            ],
          ),
        );
        if (proceed == true) {
          await _generateSchedule(force: true);
        }
        return;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not generate schedule.')),
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

  Future<void> _regenerateSchedule({
    RegenerateScheduleResult? retryResult,
    bool force = false,
  }) async {
    var result = retryResult;
    if (result == null) {
      result = await showDialog<RegenerateScheduleResult>(
        context: context,
        builder: (ctx) => RegenerateScheduleDialog(
          currentScheduleType: _league!['schedule_type'] ?? 'round_robin',
          currentMatchesPerPlayer: _league!['matches_per_player'],
          isSingles: _league!['format'] == 'singles',
        ),
      );
      if (result == null) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          title: const Text('Confirm regeneration?'),
          content: const Text(
            'This wipes ALL match history for this tournament — every confirmed result, rating change, and point awarded so far will be reversed — and replaces it with a fresh, all-pending fixture list. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Wipe & Regenerate',
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _regenerating = true);
    try {
      final res = await ApiClient.post(
        '/leagues/${widget.leagueId}/regenerate-schedule',
        body: {
          'scheduleType': result.scheduleType,
          'matchesPerPlayer': result.matchesPerPlayer,
          'force': force,
        },
      );

      if (!mounted) return;
      if (res.statusCode == 201 || res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.data?['message'] ?? 'Schedule regenerated.'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadAll();
      } else if (res.data is Map && res.data['estimatedMatches'] != null) {
        setState(() => _regenerating = false);
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            title: const Text('That\'s a lot of matches'),
            content: Text('${res.data['error']} Continue anyway?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Generate Anyway'),
              ),
            ],
          ),
        );
        if (proceed == true) {
          await _regenerateSchedule(retryResult: result, force: true);
        }
        return;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not regenerate schedule.')),
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
      if (mounted) setState(() => _regenerating = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('Delete this tournament?'),
        content: const Text(
          'This permanently deletes the tournament, its schedule, and all match history.',
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
    setState(() => _deleting = true);
    try {
      final res = await ApiClient.delete('/leagues/${widget.leagueId}');

      if (!mounted) return;
      if (res.statusCode == 200) {
        Navigator.pop(context, 'deleted');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not delete tournament.')),
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

  // GAP-12 — clones this tournament's configuration into a brand-new one for
  // a new season (name + dates only; no matches/schedule/groups are copied).
  Future<void> _showCloneDialog() async {
    final nameController = TextEditingController(
      text: '${_league!['name']} (New Season)',
    );
    DateTime? start;
    DateTime? end;
    bool copyRoster = false;
    bool submitting = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          title: const Text('Start next season'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Tournament Name'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: now.add(const Duration(days: 1)),
                            firstDate: now,
                            lastDate: now.add(const Duration(days: 730)),
                          );
                          if (picked != null) {
                            setDialogState(() => start = picked);
                          }
                        },
                        child: Text(
                          start == null
                              ? 'Start date'
                              : formatDateOnly(start!.toIso8601String()),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: start ?? now.add(const Duration(days: 1)),
                            firstDate: now,
                            lastDate: now.add(const Duration(days: 730)),
                          );
                          if (picked != null) {
                            setDialogState(() => end = picked);
                          }
                        },
                        child: Text(
                          end == null
                              ? 'End date'
                              : formatDateOnly(end!.toIso8601String()),
                        ),
                      ),
                    ),
                  ],
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: copyRoster,
                  onChanged: (v) => setDialogState(() => copyRoster = v ?? false),
                  title: const Text('Copy the current roster'),
                  subtitle: const Text(
                    'Everyone joins fresh with 0 points. Matches and schedules are never copied.',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (nameController.text.trim().isEmpty ||
                          start == null ||
                          end == null) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Enter a name and both dates.'),
                          ),
                        );
                        return;
                      }
                      if (end!.isBefore(start!)) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('End date must be after start date.'),
                          ),
                        );
                        return;
                      }
                      setDialogState(() => submitting = true);
                      final res = await ApiClient.post(
                        '/leagues/${widget.leagueId}/clone',
                        body: {
                          'name': nameController.text.trim(),
                          'seasonStart': start!.toIso8601String().split('T')[0],
                          'seasonEnd': end!.toIso8601String().split('T')[0],
                          'copyRoster': copyRoster,
                        },
                      );
                      if (!ctx.mounted) return;
                      if (res.statusCode == 201) {
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('New season created.'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LeagueDetailScreen(
                              leagueId: res.data['league']['id'],
                            ),
                          ),
                        );
                      } else {
                        setDialogState(() => submitting = false);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(
                              res.errorOr('Could not create the new season.'),
                            ),
                          ),
                        );
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  // GAP-07 — fetches a CSV from the backend, writes it to a temp file, and
  // hands it to the OS share sheet. The backend returns { filename, csv } as
  // JSON (not a raw text/csv body) since ApiClient always jsonDecodes.
  Future<void> _exportCsv(String type) async {
    HapticFeedback.selectionClick();
    final res = await ApiClient.get(
      '/leagues/${widget.leagueId}/export',
      queryParams: {'type': type},
    );
    if (!mounted) return;
    if (res.statusCode != 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.errorOr('Could not export.'))),
      );
      return;
    }

    // Everything past the status check used to be un-guarded, so a bad
    // response shape or a share-sheet/file-write failure on the device
    // failed completely silently — "the button does nothing." Surfacing
    // whatever actually goes wrong instead of swallowing it.
    //
    // Building the XFile straight from bytes (not writing to a temp file
    // first) rather than the path_provider route this used to take —
    // path_provider's getTemporaryDirectory() has no web implementation,
    // so exporting from a browser threw MissingPluginException every time.
    // XFile.fromData works identically on every platform since it never
    // touches the filesystem at all.
    try {
      final filename = res.data['filename'] as String?;
      final csv = res.data['csv'] as String?;
      if (filename == null || csv == null) {
        throw const FormatException('Export response was missing filename/csv.');
      }

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(csv)),
              name: filename,
              mimeType: 'text/csv',
            ),
          ],
          text: filename,
        ),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not export: $err'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _confirmLeave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('Leave this tournament?'),
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

    HapticFeedback.mediumImpact();
    setState(() => _leaving = true);
    try {
      final res = await ApiClient.post('/leagues/${widget.leagueId}/leave');

      if (!mounted) return;
      if (res.statusCode == 200) {
        Navigator.pop(context, 'left');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not leave tournament.')),
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

  Future<void> _confirmCompleteTournament() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('Mark tournament completed?'),
        content: const Text(
          'This makes the tournament read-only — no new joins, partner requests, schedule/bracket changes, or new match reports. Everything already recorded (matches, ratings, points) stays exactly as it is. You can reactivate it later if needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark Completed'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    HapticFeedback.mediumImpact();
    setState(() => _completing = true);
    try {
      final res = await ApiClient.post('/leagues/${widget.leagueId}/complete');

      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tournament marked completed.'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadAll();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not mark completed.')),
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
      if (mounted) setState(() => _completing = false);
    }
  }

  Future<void> _confirmReactivateTournament() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('Reactivate this tournament?'),
        content: const Text(
          'This makes the tournament active again — players can rejoin, and you can resume schedule and match activity.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    HapticFeedback.mediumImpact();
    setState(() => _completing = true);
    try {
      final res = await ApiClient.post(
        '/leagues/${widget.leagueId}/reactivate',
      );

      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tournament reactivated.'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadAll();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not reactivate.')),
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
      if (mounted) setState(() => _completing = false);
    }
  }

  // Playoff matches never have their players manually edited here (bracket
  // progression fills those slots), so unlike _openEditFixtureDialog this
  // only ever touches scheduled_time/venue.
  Future<void> _editPlayoffSchedule(
    dynamic m, {
    Map<String, dynamic>? overrideResult,
    bool force = false,
  }) async {
    final result =
        overrideResult ??
        await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (ctx) => _EditPlayoffScheduleDialog(
            initialScheduledTime: m['scheduled_time'],
            initialVenue: m['venue'],
          ),
        );
    if (result == null) return;

    HapticFeedback.lightImpact();
    try {
      final res = await ApiClient.put(
        '/playoffs/match/${m['id']}/schedule',
        body: {
          'scheduledTime': result['scheduledTime'],
          'venue': result['venue'],
          if (force) 'force': true,
        },
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Match schedule updated.'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadAll();
      } else if (res.statusCode == 409 && res.data is Map && res.data['conflicts'] != null) {
        if (await _confirmScheduleConflict(res.data['conflicts'])) {
          await _editPlayoffSchedule(m, overrideResult: result, force: true);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not update schedule.')),
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

  Future<void> _reportKnockoutMatch(int matchId) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _SelfReportSetsDialog(unitLabel: _unitLabel),
    );
    if (result == null) return;

    HapticFeedback.lightImpact();
    try {
      final res = await ApiClient.post(
        '/playoffs/match/$matchId/report',
        body: result,
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Result reported!'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadAll();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not report.')),
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

  Future<void> _hostReportKnockoutMatch(
    int matchId,
    String p1Name,
    String p2Name,
  ) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _HostReportSetsDialog(
        player1Name: p1Name,
        player2Name: p2Name,
        unitLabel: _unitLabel,
      ),
    );
    if (result == null) return;

    HapticFeedback.lightImpact();
    try {
      final res = await ApiClient.post(
        '/playoffs/match/$matchId/report-as-host',
        body: result,
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Match confirmed!'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadAll();
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

  Future<void> _confirmKnockoutMatch(int matchId) async {
    HapticFeedback.lightImpact();
    try {
      final res = await ApiClient.post('/playoffs/match/$matchId/confirm');
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Match confirmed!'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadAll();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not confirm.')),
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

  Future<void> _rejectKnockoutMatch(int matchId) async {
    HapticFeedback.mediumImpact();
    try {
      final res = await ApiClient.post('/playoffs/match/$matchId/reject');
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Result rejected.'),
            backgroundColor: AppColors.warning,
          ),
        );
        _loadAll();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not reject.')),
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
      final res = await ApiClient.delete(
        '/leagues/${widget.leagueId}/schedule/$scheduledMatchId',
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Match removed.'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadAll();
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

  // Shared by every schedule-save call site (round-robin, group, playoff) —
  // shows the conflicting fixtures a 409 came back with and asks whether to
  // save anyway, mirroring the existing "Generate Anyway" pattern used for
  // large round-robin generation (see _generateSchedule above).
  Future<bool> _confirmScheduleConflict(dynamic conflicts) async {
    final List list = conflicts is List ? conflicts : [];
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('Scheduling conflict'),
        content: Text(
          list.isEmpty
              ? 'One or more players already have a match scheduled around this time.'
              : list
                    .map(
                      (c) =>
                          '${c['league_name']} · ${_formatScheduledTime(c['scheduled_time'])}',
                    )
                    .join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Schedule Anyway'),
          ),
        ],
      ),
    );
    return proceed == true;
  }

  Future<void> _openEditFixtureDialog(
    dynamic f, {
    Map<String, dynamic>? overrideResult,
    bool force = false,
  }) async {
    final result =
        overrideResult ??
        await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (ctx) => _EditFixtureDialog(
            format: _league!['format'],
            sport: _league!['sport'],
            members: _leaderboard,
            initialPlayer1Id: f['player1_id'],
            initialPlayer1PartnerId: f['player1_partner_id'],
            initialPlayer2Id: f['player2_id'],
            initialPlayer2PartnerId: f['player2_partner_id'],
            initialScheduledTime: f['scheduled_time'],
            initialVenue: f['venue'],
          ),
        );
    if (result == null) return;

    HapticFeedback.lightImpact();
    try {
      final res = await ApiClient.put(
        '/leagues/${widget.leagueId}/schedule/${f['id']}',
        body: {
          'player1Id': result['player1Id'],
          'player1PartnerId': result['player1PartnerId'],
          'player2Id': result['player2Id'],
          'player2PartnerId': result['player2PartnerId'],
          'scheduledTime': result['scheduledTime'],
          'venue': result['venue'],
          if (force) 'force': true,
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
        _loadAll();
      } else if (res.statusCode == 409 && res.data is Map && res.data['conflicts'] != null) {
        if (await _confirmScheduleConflict(res.data['conflicts'])) {
          await _openEditFixtureDialog(f, overrideResult: result, force: true);
        }
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

  Future<void> _openEditScoreDialog(dynamic f) async {
    final team1Name = f['player1_partner_username'] != null
        ? '${f['player1_username']} & ${f['player1_partner_username']}'
        : f['player1_username'];
    final team2Name = f['player2_partner_username'] != null
        ? '${f['player2_username']} & ${f['player2_partner_username']}'
        : f['player2_username'];

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
      builder: (ctx) => _HostReportSetsDialog(
        player1Name: team1Name,
        player2Name: team2Name,
        title: 'Edit Score',
        unitLabel: _unitLabel,
        initialSets: initialSets,
        initialPhotoUrl: f['photo_url'],
      ),
    );
    if (result == null) return;

    HapticFeedback.lightImpact();
    try {
      final res = await ApiClient.put(
        '/matches/${f['match_id']}/edit',
        body: result,
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res.data?['warning'] ??
                  'Score updated and ratings recalculated.',
            ),
            backgroundColor: res.data?['warning'] != null
                ? AppColors.warning
                : AppColors.success,
          ),
        );
        _loadAll();
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

  // Reports a brand-new result directly from a specific fixture card (host
  // mode) — no separate opponent-picking screen needed, since the fixture
  // already tells us exactly who's playing.
  Future<void> _hostReportFixture(dynamic f) async {
    final team1Name = f['player1_partner_username'] != null
        ? '${f['player1_username']} & ${f['player1_partner_username']}'
        : f['player1_username'];
    final team2Name = f['player2_partner_username'] != null
        ? '${f['player2_username']} & ${f['player2_partner_username']}'
        : f['player2_username'];

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _HostReportSetsDialog(
        player1Name: team1Name,
        player2Name: team2Name,
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
          'player1Won': result['player1Won'],
          if (result['isWalkover'] == true) 'isWalkover': true,
          if (result['isWalkover'] != true) 'player1Units': result['player1Units'],
          if (result['isWalkover'] != true) 'player2Units': result['player2Units'],
          if (result['isWalkover'] != true) 'setScores': result['setScores'],
          if (result['photoUrl'] != null) 'photoUrl': result['photoUrl'],
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
        _loadAll();
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

  Future<void> _editMyReport(dynamic f) async {
    final iAmTeam1 =
        f['player1_id'] == _currentUserId ||
        f['player1_partner_id'] == _currentUserId;
    final team2Name = f['player2_partner_username'] != null
        ? '${f['player2_username']} & ${f['player2_partner_username']}'
        : f['player2_username'];
    final team1Name = f['player1_partner_username'] != null
        ? '${f['player1_username']} & ${f['player1_partner_username']}'
        : f['player1_username'];
    final opponentName = iAmTeam1 ? team2Name : team1Name;

    List<Map<String, int>>? initialSets;
    try {
      if (f['set_scores'] != null) {
        final List raw = jsonDecode(f['set_scores']);
        initialSets = raw
            .map<Map<String, int>>(
              (s) => {
                'me': iAmTeam1 ? s['me'] as int : s['opponent'] as int,
                'opponent': iAmTeam1 ? s['opponent'] as int : s['me'] as int,
              },
            )
            .toList();
      }
    } catch (err) {
      initialSets = null;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _SelfReportSetsDialog(
        title: 'Edit My Report',
        opponentName: opponentName,
        unitLabel: _unitLabel,
        initialSets: initialSets,
        initialPhotoUrl: f['photo_url'],
      ),
    );
    if (result == null) return;

    try {
      final res = await ApiClient.put(
        '/matches/${f['match_id']}/edit-report',
        body: result,
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report updated.'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadAll();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not update report.')),
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
        _loadAll();
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

  Future<void> _confirmRemovePlayer(int userId, String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text('Remove $username?'),
        content: const Text(
          'They will be removed from the leaderboard and schedule. Their unplayed matches will be removed too, but confirmed match history and rating changes stay as-is.',
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
      final res = await ApiClient.delete(
        '/leagues/${widget.leagueId}/members/$userId',
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Player removed.'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadAll();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not remove player.')),
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

  Future<void> _toggleCoHost(dynamic player) async {
    final isCoHost = player['is_co_host'] == true;
    HapticFeedback.selectionClick();
    try {
      final res = isCoHost
          ? await ApiClient.delete(
              '/leagues/${widget.leagueId}/co-hosts/${player['id']}',
            )
          : await ApiClient.post(
              '/leagues/${widget.leagueId}/co-hosts',
              body: {'userId': player['id']},
            );
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCoHost ? 'Co-host removed.' : 'Co-host added.',
            ),
            backgroundColor: AppColors.success,
          ),
        );
        _loadAll();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not update co-host status.')),
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

  String _formatSport(String sport) => sport
      .split('_')
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

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

  String? _ratingFor(int? playerId) {
    if (playerId == null) return null;
    for (final p in _leaderboard) {
      if (p['id'] == playerId) {
        return formatRating(_league!['sport'], p['rating']);
      }
    }
    return null;
  }

  Widget? _buildActionButton(bool isHost) {
    if (_isKnockout) return null;
    if (_isCompleted) return null;

    final hostEntersScores = _league!['host_enters_scores'] == true;

    if (_isCustom && isHost) {
      return FloatingActionButton.extended(
        onPressed: () async {
          HapticFeedback.lightImpact();
          final added = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddManualMatchScreen(
                leagueId: widget.leagueId,
                format: _league!['format'],
                members: _leaderboard,
              ),
            ),
          );
          if (added == true) _loadAll();
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Match'),
      );
    }

    if (hostEntersScores) {
      // Host scoring is now done inline per-fixture (see the "Enter Score"
      // button on each unplayed fixture card) rather than through a
      // separate screen, so no FAB is needed here.
      return null;
    }

    if (!_isMember) return null;

    return FloatingActionButton.extended(
      onPressed: () async {
        HapticFeedback.lightImpact();
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
        if (reported == true) {
          _loadAll();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Score submitted — waiting for your opponent to confirm.',
                ),
                backgroundColor: AppColors.success,
              ),
            );
          }
        }
      },
      icon: const Icon(Icons.sports_score),
      label: const Text('Report'),
    );
  }

  @override
  Widget build(BuildContext context) {
    // isHost is deliberately widened to mean "host or co-host" — every
    // downstream consumer of it (this file's own actions, plus the 4 screens
    // it's prop-drilled into: groups_overview_screen.dart, playoffs_screen.dart,
    // partner_selection_screen.dart, widgets/bracket_view.dart) just gates
    // "can perform privileged actions," which a co-host should pass too.
    // _isPrimaryHost below is the narrower check for the handful of things
    // that stay creator-only (delete league, manage co-hosts).
    final myMembership = _leaderboard.firstWhere(
      (p) => p['id'] == _currentUserId,
      orElse: () => null,
    );
    final isHost = _isPrimaryHost || (myMembership?['is_co_host'] == true);

    if (_loading) {
      return const Scaffold(body: SkeletonList());
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tournament')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => _loadAll(showFullLoading: true),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
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
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit tournament',
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditLeagueScreen(
                        league: _league!,
                        hasConfirmedMatches: _hasConfirmedMatches,
                      ),
                    ),
                  );
                  if (result == true) _loadAll();
                },
              ),
            if (isHost)
              IconButton(
                icon: const Icon(Icons.person_add_alt_outlined),
                tooltip: 'Add players',
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddPlayersScreen(
                        leagueId: widget.leagueId,
                        sport: _league!['sport'],
                        genderCategory: _league!['gender_category'],
                      ),
                    ),
                  );
                  if (result != null) _loadAll();
                },
              ),
            // Deliberately _isPrimaryHost, not the widened isHost — deleting
            // the league stays creator-only even for a co-host.
            if (_isPrimaryHost)
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
                tooltip: 'Delete tournament',
                onPressed: _deleting ? null : _confirmDelete,
              ),
            if (isHost || _isMember)
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (value) {
                  if (value == 'clone') _showCloneDialog();
                  if (value == 'export_standings') _exportCsv('standings');
                  if (value == 'export_fixtures') _exportCsv('fixtures');
                  if (value == 'audit_log') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AuditLogScreen(leagueId: widget.leagueId),
                      ),
                    );
                  }
                },
                itemBuilder: (ctx) => [
                  if (isHost)
                    const PopupMenuItem(
                      value: 'clone',
                      child: Text('Start next season'),
                    ),
                  const PopupMenuItem(
                    value: 'export_standings',
                    child: Text('Export standings (CSV)'),
                  ),
                  const PopupMenuItem(
                    value: 'export_fixtures',
                    child: Text('Export fixtures (CSV)'),
                  ),
                  if (isHost)
                    const PopupMenuItem(
                      value: 'audit_log',
                      child: Text('Activity log'),
                    ),
                ],
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
            _isKnockout ? _buildKnockoutTab(isHost) : _buildScheduleTab(isHost),
            _buildMyMatchesTab(isHost),
          ],
        ),
        floatingActionButton: _buildActionButton(isHost),
      ),
    );
  }

  // GAP-15 — announcements board. A one-way board (host/co-host posts,
  // members read), not chat — this card shows just the latest post with a
  // "See all" expansion, plus a compose action for admins.
  Widget _buildAnnouncementsCard(bool isHost) {
    if (_announcements.isEmpty && !isHost) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final latest = _announcements.isNotEmpty ? _announcements.first : null;

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder(isDark)),
        boxShadow: AppShadows.card(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.campaign_outlined, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Announcements',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              if (isHost)
                IconButton(
                  icon: const Icon(Icons.add_comment_outlined, size: 20),
                  tooltip: 'Post announcement',
                  onPressed: _composeAnnouncement,
                ),
            ],
          ),
          if (latest == null)
            const Text(
              'No announcements yet.',
              style: TextStyle(fontSize: 12, color: AppColors.textGrey),
            )
          else ...[
            Text(latest['body'], maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              '${latest['author_username'] ?? 'Host'} · '
              '${formatRelativeTime(latest['updated_at'] ?? latest['created_at'])}'
              '${latest['updated_at'] != null ? ' (edited)' : ''}',
              style: const TextStyle(fontSize: 11, color: AppColors.textGrey),
            ),
            // Was gated on length > 1 alone — that's fine for a plain
            // "see the rest" link, but it's also the only way into the
            // edit/delete menu, so a host with exactly one announcement had
            // no way to reach it at all. Keep it hidden for a non-host with
            // just one (nothing more to see, nothing to manage).
            if (_announcements.length > 1 || isHost)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _showAllAnnouncements(isHost),
                  child: Text(
                    _announcements.length > 1
                        ? 'See all (${_announcements.length})'
                        : 'Manage',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // `existing` set means edit-in-place (PUT, pre-filled) rather than a
  // brand-new post (POST, blank) — same dialog either way.
  Future<void> _composeAnnouncement({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final controller = TextEditingController(text: existing?['body'] ?? '');
    final posted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text(isEdit ? 'Edit announcement' : 'Post announcement'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'e.g. Courts have changed to Court 3, starting at 7pm.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;
              final res = isEdit
                  ? await ApiClient.put(
                      '/leagues/${widget.leagueId}/announcements/${existing['id']}',
                      body: {'body': controller.text.trim()},
                    )
                  : await ApiClient.post(
                      '/leagues/${widget.leagueId}/announcements',
                      body: {'body': controller.text.trim()},
                    );
              if (!ctx.mounted) return;
              Navigator.pop(ctx, res.statusCode == (isEdit ? 200 : 201));
            },
            child: Text(isEdit ? 'Save' : 'Post'),
          ),
        ],
      ),
    );
    if (posted == true) _loadAll();
  }

  Future<void> _deleteAnnouncement(int announcementId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('Delete this announcement?'),
        content: const Text('Members who already saw it keep their notification.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final res = await ApiClient.delete(
      '/leagues/${widget.leagueId}/announcements/$announcementId',
    );
    if (!mounted) return;
    if (res.statusCode == 200) {
      _loadAll();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.errorOr('Could not delete the announcement.')),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _showAllAnnouncements(bool isHost) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        expand: false,
        builder: (ctx, scrollController) => ListView.separated(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: _announcements.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final a = _announcements[index];
            final edited = a['updated_at'] != null;
            return ListTile(
              title: Text(a['body']),
              subtitle: Text(
                '${a['author_username'] ?? 'Host'} · '
                '${formatRelativeTime(edited ? a['updated_at'] : a['created_at'])}'
                '${edited ? ' (edited)' : ''}',
              ),
              trailing: isHost
                  ? PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 20),
                      onSelected: (value) {
                        // The bottom sheet doesn't live-refresh its own list
                        // when _announcements changes underneath it (no
                        // StatefulBuilder here) — close it first so the
                        // reopened card/sheet picks up the reload cleanly,
                        // same as the compose flow already does.
                        Navigator.pop(ctx);
                        if (value == 'edit') {
                          _composeAnnouncement(existing: a);
                        } else if (value == 'delete') {
                          _deleteAnnouncement(a['id']);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete', style: TextStyle(color: AppColors.danger)),
                        ),
                      ],
                    )
                  : null,
            );
          },
        ),
      ),
    );
  }

  Widget _buildLeaderboardTab(bool isHost) {
    final academyName = _league!['academy_name'];
    final hostUsername = _league!['host_username'];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark;

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.cardBorder(isDark)),
              boxShadow: AppShadows.card(isDark),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _league!['name'],
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: primaryTextColor,
                        ),
                      ),
                    ),
                    if (_isCompleted)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade600,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          'COMPLETED',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatSport(_league!['sport'])} · ${_league!['area']}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: primaryTextColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatDateOnly(_league!['season_start'])} to ${formatDateOnly(_league!['season_end'])} · ${_leaderboard.length} players · ${_league!['format']} · ${_league!['gender_category'] == 'mens' ? "Men's" : _league!['gender_category'] == 'mixed' ? 'Mixed' : "Women's"}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      academyName != null
                          ? Icons.school_outlined
                          : Icons.person_outline,
                      size: 14,
                      color: AppColors.textGrey,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        academyName != null
                            ? 'Hosted by $academyName'
                            : 'Hosted by $hostUsername',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (_league!['host_phone'] != null) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      launchPhoneCall(_league!['host_phone'] as String);
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.phone_outlined,
                          size: 14,
                          color: AppColors.primaryLight,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _league!['host_phone'],
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primaryLight,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_isLeagueStyle) ...[
                  const SizedBox(height: 4),
                  Text(
                    _pointsSubtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textGrey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ] else if (_isKnockout) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Knockout bracket',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textGrey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                if (_league!['is_private'] == true && isHost) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.cardBorder(isDark)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.key_outlined,
                          size: 16,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Join code: ${_league!['join_code']}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).textTheme.bodyMedium?.color,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy join code (just the code, no link)',
                          icon: const Icon(Icons.copy_outlined, size: 18),
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            Clipboard.setData(
                              ClipboardData(text: _league!['join_code']),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Join code copied — use Share instead to send a tappable link too.',
                                ),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          },
                        ),
                        IconButton(
                          tooltip: 'Share join code and link',
                          icon: const Icon(Icons.share_outlined, size: 18),
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            SharePlus.instance.share(
                              ShareParams(
                                text:
                                    'Join my tournament "${_league!['name']}" on PlayMySet!\n'
                                    'Join code: ${_league!['join_code']}\n'
                                    '(Tap this link if it opens the app: playmyset://join/${_league!['join_code']})',
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ] else if (_league!['is_private'] != true) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        SharePlus.instance.share(
                          ShareParams(
                            text:
                                'Check out "${_league!['name']}" on PlayMySet!\n'
                                '(Tap this link if it opens the app: playmyset://league/${widget.leagueId})',
                          ),
                        );
                      },
                      icon: const Icon(Icons.share_outlined, size: 16),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _buildAnnouncementsCard(isHost),
          if (isHost)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                onPressed: _completing
                    ? null
                    : (_isCompleted
                          ? _confirmReactivateTournament
                          : _confirmCompleteTournament),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _isCompleted
                      ? AppColors.accent
                      : Colors.grey.shade700,
                  side: BorderSide(
                    color: _isCompleted
                        ? AppColors.accent
                        : Colors.grey.shade400,
                  ),
                ),
                icon: _completing
                    ? SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _isCompleted
                              ? AppColors.accent
                              : Colors.grey.shade700,
                        ),
                      )
                    : Icon(
                        _isCompleted
                            ? Icons.refresh
                            : Icons.check_circle_outline,
                      ),
                label: Text(
                  _isCompleted
                      ? 'Reactivate Tournament'
                      : 'Mark Tournament Completed',
                ),
              ),
            ),
          if (_isDoublesLeague &&
              _partnerMode != 'host_auto' &&
              !_isCompleted &&
              (_isMember || isHost))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                onPressed: () async {
                  HapticFeedback.selectionClick();
                  final changed = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PartnerSelectionScreen(
                        leagueId: widget.leagueId,
                        partnerMode: _partnerMode,
                        isHost: isHost,
                        currentUserId: _currentUserId,
                      ),
                    ),
                  );
                  if (changed == true) _loadAll();
                },
                icon: const Icon(Icons.group_add_outlined),
                label: Text(
                  _partnerMode == 'host_manual' && isHost
                      ? 'Manage Partners'
                      : 'Choose Your Partner',
                ),
              ),
            ),
          if (!_isMember && _isCompleted) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.grey.shade700,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'This tournament has ended and is no longer accepting new players.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else if (!_isMember) ...[
            if (_registrationMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 16,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _registrationMessage!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ElevatedButton.icon(
                onPressed: (_joining || _registrationMessage != null)
                    ? null
                    : _joinLeague,
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
                label: const Text('Join Tournament'),
              ),
            ),
          ] else if (!isHost)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                onPressed: _leaving ? null : _confirmLeave,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                ),
                icon: _leaving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          color: AppColors.danger,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.exit_to_app),
                label: const Text('Leave Tournament'),
              ),
            ),
          if (_isMember &&
              _isLeagueStyle &&
              !_isCompleted &&
              _league!['schedule_type'] != 'groups')
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PlayoffsScreen(
                        leagueId: widget.leagueId,
                        isHost: isHost,
                        format: _league!['format'],
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.emoji_events_outlined),
                label: const Text('Playoffs'),
              ),
            ),
          if (isHost && _league!['schedule_type'] == 'groups' && !_isCompleted)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                onPressed: () async {
                  HapticFeedback.selectionClick();
                  final changed = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          GroupManagementScreen(leagueId: widget.leagueId),
                    ),
                  );
                  if (changed == true) _loadAll();
                },
                icon: const Icon(Icons.groups_outlined),
                label: const Text('Manage Groups'),
              ),
            ),
          if (_isMember && _league!['schedule_type'] == 'groups')
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GroupsOverviewScreen(
                        leagueId: widget.leagueId,
                        isHost: isHost,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.leaderboard_outlined),
                label: const Text('View Groups & Standings'),
              ),
            ),
          if (isHost &&
              !_isCustom &&
              !_isCompleted &&
              _league!['schedule_type'] != 'groups' &&
              ((_isKnockout && _bracket.isEmpty) ||
                  (!_isKnockout && _schedule.isEmpty)))
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
                    : Text(
                        _isKnockout ? 'Generate Bracket' : 'Generate Schedule',
                      ),
              ),
            ),
          if (_isDoublesLeague)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Pairs'),
                    selected: _showPairs,
                    onSelected: (v) => setState(() => _showPairs = true),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Individual'),
                    selected: !_showPairs,
                    onSelected: (v) => setState(() => _showPairs = false),
                  ),
                ],
              ),
            ),
          if (_isDoublesLeague && _showPairs)
            _buildPairLeaderboardList(isDark)
          else if (_leaderboard.isEmpty)
            const FriendlyEmptyState(
              icon: Icons.people_outline,
              title: 'No members yet',
              subtitle: 'Players will show up here once they join.',
            )
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
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.cardBorder(isDark)),
                  boxShadow: AppShadows.card(isDark),
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 0,
                    ),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PlayerProfileScreen(userId: player['id']),
                        ),
                      );
                    },
                    leading: SizedBox(
                      width: 72,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
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
                          const SizedBox(width: 6),
                          _playerAvatar(player, 15),
                        ],
                      ),
                    ),
                    title: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            player['username'],
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (player['is_guest'] == true) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.textGrey.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Guest',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textGrey,
                              ),
                            ),
                          ),
                        ],
                        if (player['is_co_host'] == true) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Co-Host',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      '${player['matches_played']} matches · ${player['wins']}W ${player['losses']}L',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (_isLeagueStyle && _pointsEnabled)
                              PointsBadge(points: player['points']),
                            Text(
                              'Rating: ${formatRating(_league!['sport'], player['rating'])}',
                              style: TextStyle(
                                fontSize: _isLeagueStyle ? 10 : 13,
                                fontWeight: _isLeagueStyle
                                    ? FontWeight.normal
                                    : FontWeight.bold,
                                color: _isLeagueStyle
                                    ? AppColors.textGrey
                                    : AppColors.accent,
                              ),
                            ),
                          ],
                        ),
                        // Deliberately _isPrimaryHost, not the widened isHost —
                        // granting/revoking co-host status stays creator-only,
                        // so co-hosts can't promote/demote each other.
                        if (_isPrimaryHost &&
                            player['id'] != _currentUserId &&
                            player['is_guest'] != true)
                          IconButton(
                            icon: Icon(
                              player['is_co_host'] == true
                                  ? Icons.remove_moderator_outlined
                                  : Icons.add_moderator_outlined,
                              size: 20,
                              color: AppColors.accent,
                            ),
                            tooltip: player['is_co_host'] == true
                                ? 'Remove co-host'
                                : 'Make co-host',
                            onPressed: () => _toggleCoHost(player),
                          ),
                        if (isHost && player['id'] != _currentUserId)
                          IconButton(
                            icon: const Icon(
                              Icons.person_remove_outlined,
                              size: 20,
                              color: AppColors.danger,
                            ),
                            tooltip: 'Remove player',
                            onPressed: () => _confirmRemovePlayer(
                              player['id'],
                              player['username'],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _playerAvatar(dynamic player, double radius) {
    return PlayerAvatar(
      username: (player['username'] ?? '?') as String,
      profilePicUrl: player['profile_pic_url'] as String?,
      radius: radius,
    );
  }

  // No single "team profile" screen exists, so let the host pick which
  // partner's profile to open instead of always defaulting to one of them.
  Future<void> _choosePairMember(BuildContext context, dynamic pair) async {
    final userId = await showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 12, bottom: 4),
              child: Text(
                'View whose profile?',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            ListTile(
              leading: _playerAvatar({
                'username': pair['player_a_username'],
                'profile_pic_url': pair['player_a_profile_pic_url'],
              }, 16),
              title: Text(pair['player_a_username'] ?? ''),
              onTap: () => Navigator.pop(ctx, pair['player_a_id'] as int),
            ),
            ListTile(
              leading: _playerAvatar({
                'username': pair['player_b_username'],
                'profile_pic_url': pair['player_b_profile_pic_url'],
              }, 16),
              title: Text(pair['player_b_username'] ?? ''),
              onTap: () => Navigator.pop(ctx, pair['player_b_id'] as int),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (userId == null || !context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlayerProfileScreen(userId: userId)),
    );
  }

  Widget _buildPairLeaderboardList(bool isDark) {
    if (_pairLeaderboard == null || _pairLeaderboard!.isEmpty) {
      return const FriendlyEmptyState(
        icon: Icons.groups_outlined,
        title: 'No confirmed doubles matches yet',
        subtitle: 'Pairs will appear here once matches are played.',
      );
    }

    return Column(
      children: _pairLeaderboard!.asMap().entries.map((entry) {
        final rank = entry.key + 1;
        final pair = entry.value;
        final rankColor = rank == 1
            ? const Color(0xFFB8860B)
            : rank == 2
            ? const Color(0xFF9CA3AF)
            : rank == 3
            ? const Color(0xFFB08D57)
            : Colors.grey.shade200;
        final rankTextColor = rank <= 3 ? Colors.white : AppColors.textDark;

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.cardBorder(isDark)),
            boxShadow: AppShadows.card(isDark),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 0,
              ),
              // There's no single "team profile" screen, so tapping a pair
              // asks which partner's profile to open rather than silently
              // picking one.
              onTap: () {
                HapticFeedback.selectionClick();
                _choosePairMember(context, pair);
              },
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
                '${pair['player_a_username']} & ${pair['player_b_username']}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: Text(
                '${pair['matches_played']} matches · ${pair['wins']}W ${pair['losses']}L',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: Text(
                'Avg: ${formatRating(_league!['sport'], pair['avg_rating'])}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKnockoutTab(bool isHost) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!_isMember && !isHost) {
      return const FriendlyEmptyState(
        icon: Icons.lock_outline,
        title: 'Join this tournament to see the bracket.',
      );
    }
    if (_bracket.isEmpty) {
      return FriendlyEmptyState(
        icon: Icons.emoji_events_outlined,
        title: 'No bracket yet',
        subtitle: isHost
            ? 'Generate one from the Leaderboard tab.'
            : "The host hasn't generated the bracket yet.",
      );
    }

    final hostEntersScores = _league!['host_enters_scores'] == true;
    final Map<int, List<dynamic>> rounds = {};
    for (final m in _bracket) {
      rounds.putIfAbsent(m['round_number'], () => []).add(m);
    }
    final totalRounds = rounds.keys.reduce((a, b) => a > b ? a : b);

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: rounds.entries.map((entry) {
          final roundNumber = entry.key;
          final roundName = roundNumber == totalRounds
              ? 'Final'
              : roundNumber == totalRounds - 1
              ? 'Semifinal'
              : 'Round $roundNumber';

          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(roundName, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                ...entry.value.map((m) {
                  final isDoublesMatch = m['player1_partner_username'] != null;
                  final p1 = isDoublesMatch
                      ? '${m['player1_username'] ?? 'TBD'}${m['player1_partner_username'] != null ? ' & ${m['player1_partner_username']}' : ''}'
                      : (m['player1_username'] ?? 'TBD');
                  final p2 = isDoublesMatch
                      ? '${m['player2_username'] ?? 'TBD'}${m['player2_partner_username'] != null ? ' & ${m['player2_partner_username']}' : ''}'
                      : (m['player2_username'] ?? 'TBD');
                  final isReady = m['status'] == 'ready';
                  final isReported = m['status'] == 'reported';
                  final isConfirmed = m['status'] == 'confirmed';
                  final involvesMe =
                      m['player1_id'] == _currentUserId ||
                      m['player2_id'] == _currentUserId ||
                      m['player1_partner_id'] == _currentUserId ||
                      m['player2_partner_id'] == _currentUserId;
                  final reportedByMe = m['reported_by'] == _currentUserId;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isConfirmed
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
                              child: Text(
                                '$p1  vs  $p2',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isConfirmed
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (isConfirmed)
                              Text(
                                'Won: ${m['winner_id'] == m['player1_id'] ? p1 : p2}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.success,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                        if (m['scheduled_time'] != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.event,
                                size: 12,
                                color: AppColors.textGrey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatScheduledTime(m['scheduled_time']),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textGrey,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (m['venue'] != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.place,
                                size: 12,
                                color: AppColors.textGrey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                m['venue'],
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textGrey,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (isHost && !_isCompleted) ...[
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => _editPlayoffSchedule(m),
                              icon: const Icon(Icons.edit_calendar, size: 15),
                              label: const Text(
                                'Edit schedule',
                                style: TextStyle(fontSize: 12),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        ],
                        if (m['is_walkover'] == true) ...[
                          const SizedBox(height: 4),
                          const Text(
                            'Walkover',
                            style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: AppColors.textGrey,
                            ),
                          ),
                        ] else if (m['set_scores'] != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _formatSetScores(m['set_scores']),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textGrey,
                            ),
                          ),
                        ],
                        if (hostEntersScores && isHost && isReady) ...[
                          const SizedBox(height: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            onPressed: () =>
                                _hostReportKnockoutMatch(m['id'], p1, p2),
                            child: const Text(
                              'Enter Score',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                        if (!hostEntersScores && isReady && involvesMe) ...[
                          const SizedBox(height: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            onPressed: () => _reportKnockoutMatch(m['id']),
                            child: const Text(
                              'Report Result',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                        if (!hostEntersScores &&
                            isReported &&
                            involvesMe &&
                            !reportedByMe) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.danger,
                                    side: const BorderSide(
                                      color: AppColors.danger,
                                    ),
                                  ),
                                  onPressed: () =>
                                      _rejectKnockoutMatch(m['id']),
                                  child: const Text(
                                    'Reject',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () =>
                                      _confirmKnockoutMatch(m['id']),
                                  child: const Text(
                                    'Confirm',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (!hostEntersScores && isReported && reportedByMe)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              'Waiting for opponent to confirm...',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textGrey,
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

  Widget _buildScheduleTab(bool isHost) {
    if (!_isMember) {
      return const FriendlyEmptyState(
        icon: Icons.lock_outline,
        title: 'Join this tournament to see the schedule.',
      );
    }

    if (_schedule.isEmpty) {
      return FriendlyEmptyState(
        icon: Icons.calendar_today_outlined,
        title: _isCustom
            ? (isHost ? 'No matches added yet' : "No matches yet")
            : (isHost ? 'No schedule yet' : "No schedule yet"),
        subtitle: _isCustom
            ? (isHost
                  ? 'Use "Add Match" below.'
                  : "The host hasn't added any matches yet.")
            : (isHost
                  ? 'Generate one from the Leaderboard tab.'
                  : "The host hasn't generated a schedule yet."),
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
        children: [
          if (isHost && !_isCustom && !_isCompleted)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: OutlinedButton.icon(
                onPressed: _regenerating ? null : _regenerateSchedule,
                icon: _regenerating
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('Regenerate Schedule'),
              ),
            ),
          ...tiers.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...entry.value.map(
                    (f) => _buildFixtureCard(
                      f,
                      showContacts: true,
                      isHost: isHost,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _bracketStatusLabel(dynamic status) {
    switch (status) {
      case 'ready':
        return 'Not played';
      case 'reported':
        return 'Awaiting confirmation';
      case 'confirmed':
        return 'Done';
      default:
        final s = status?.toString() ?? '';
        return s.isEmpty
            ? ''
            : s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');
    }
  }

  Widget _buildMyMatchesTab(bool isHost) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!_isMember) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Join this tournament to see your matches.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    if (_isKnockout) {
      final myMatches = _bracket
          .where(
            (m) =>
                m['player1_id'] == _currentUserId ||
                m['player2_id'] == _currentUserId ||
                m['player1_partner_id'] == _currentUserId ||
                m['player2_partner_id'] == _currentUserId,
          )
          .toList();
      if (myMatches.isEmpty) {
        return const FriendlyEmptyState(
          icon: Icons.emoji_events_outlined,
          title: 'No bracket matches for you yet.',
        );
      }
      return RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: myMatches.map((m) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.cardBorder(isDark)),
                boxShadow: AppShadows.card(isDark),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: TeamNameRow(
                            playerId: m['player1_id'],
                            playerName: m['player1_username'] ?? 'TBD',
                            partnerId: m['player1_partner_id'],
                            partnerName: m['player1_partner_username'],
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const Text(' vs ', style: TextStyle(fontSize: 13)),
                        Flexible(
                          child: TeamNameRow(
                            playerId: m['player2_id'],
                            playerName: m['player2_username'] ?? 'TBD',
                            partnerId: m['player2_partner_id'],
                            partnerName: m['player2_partner_username'],
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _bracketStatusLabel(m['status']),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textGrey,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
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
      return const FriendlyEmptyState(
        icon: Icons.calendar_today_outlined,
        title: 'No scheduled matches for you yet.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: myFixtures
            .map(
              (f) => _buildFixtureCard(f, showContacts: true, isHost: isHost),
            )
            .toList(),
      ),
    );
  }

  Widget _buildFixtureCard(
    dynamic f, {
    required bool showContacts,
    bool isHost = false,
  }) {
    final isDoubles = f['player1_partner_username'] != null;
    final p1Rating = _ratingFor(f['player1_id']);
    final p2Rating = _ratingFor(f['player2_id']);
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark;
    final subtleVsColor = isDark ? Colors.grey.shade400 : AppColors.textGrey;

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
                child: Row(
                  children: [
                    Flexible(
                      child: TeamNameRow(
                        playerId: f['player1_id'],
                        playerName: f['player1_username'] ?? '',
                        partnerId: f['player1_partner_id'],
                        partnerName: f['player1_partner_username'],
                        suffix: !isDoubles && p1Rating != null
                            ? ' ($p1Rating)'
                            : null,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: team1Won
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: team1Won
                              ? AppColors.success
                              : primaryTextColor,
                        ),
                      ),
                    ),
                    Text('  vs  ', style: TextStyle(fontSize: 13, color: subtleVsColor)),
                    Flexible(
                      child: TeamNameRow(
                        playerId: f['player2_id'],
                        playerName: f['player2_username'] ?? '',
                        partnerId: f['player2_partner_id'],
                        partnerName: f['player2_partner_username'],
                        suffix: !isDoubles && p2Rating != null
                            ? ' ($p2Rating)'
                            : null,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: team2Won
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: team2Won
                              ? AppColors.success
                              : primaryTextColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (f['photo_url'] != null) ...[
                MatchPhotoThumbnail(photoUrl: f['photo_url'], size: 28),
                const SizedBox(width: 6),
              ],
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
                Icon(Icons.event, size: 12, color: subtleVsColor),
                const SizedBox(width: 4),
                Text(
                  _formatScheduledTime(f['scheduled_time']),
                  style: TextStyle(fontSize: 11, color: subtleVsColor),
                ),
              ],
            ),
          ],
          if (f['venue'] != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.place, size: 12, color: subtleVsColor),
                const SizedBox(width: 4),
                Text(
                  f['venue'],
                  style: TextStyle(fontSize: 11, color: subtleVsColor),
                ),
              ],
            ),
          ],
          if (isCompleted && f['is_walkover'] == true) ...[
            const SizedBox(height: 4),
            const Text(
              'Walkover',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: AppColors.textGrey,
              ),
            ),
          ] else if (isCompleted) ...[
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
          if (!isCompleted &&
              f['match_id'] != null &&
              f['reported_player1_id'] != null &&
              involvesMe) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _editMyReport(f),
                icon: const Icon(Icons.edit_outlined, size: 15),
                label: const Text(
                  'Edit My Report',
                  style: TextStyle(fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
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
                ] else if (!_isCompleted) ...[
                  if (_league!['host_enters_scores'] == true)
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
                    onPressed: () => _openEditFixtureDialog(f),
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

class _SelfReportSetsDialog extends StatefulWidget {
  final String title;
  final String opponentName;
  final String unitLabel;
  final List<Map<String, int>>? initialSets;
  // GAP-17 — seeds the photo preview on an edit path; null on a fresh
  // report. See MatchPhotoPicker for why there's no "remove" affordance.
  final String? initialPhotoUrl;

  const _SelfReportSetsDialog({
    this.title = 'Report Result',
    this.opponentName = 'Opponent',
    this.unitLabel = 'Set',
    this.initialSets,
    this.initialPhotoUrl,
  });

  @override
  State<_SelfReportSetsDialog> createState() => _SelfReportSetsDialogState();
}

class _SelfReportSetsDialogState extends State<_SelfReportSetsDialog> {
  static const int _maxSets = 7;
  late List<_SetScore> _sets;
  String? _error;
  String? _photoUrl;

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
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        decoration: InputDecoration(
                          labelText: '${widget.unitLabel} ${index + 1} — You',
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
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        decoration: InputDecoration(
                          labelText: widget.opponentName,
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
                        tooltip: 'Remove ${widget.unitLabel} ${index + 1}',
                        onPressed: () => setState(() => _sets.removeAt(index)),
                      ),
                  ],
                ),
              );
            }),
            if (_sets.length < _maxSets)
              TextButton.icon(
                onPressed: () => setState(() => _sets.add(_SetScore())),
                icon: const Icon(Icons.add),
                label: Text('Add ${widget.unitLabel}'),
              ),
            const SizedBox(height: 12),
            MatchPhotoPicker(
              initialPhotoUrl: widget.initialPhotoUrl,
              onChanged: (dataUri) => _photoUrl = dataUri,
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
            int totalMy = 0, totalOpp = 0, setsWonByMe = 0, setsWonByOpp = 0;
            final List<Map<String, int>> setScores = [];
            for (final s in _sets) {
              final my = int.tryParse(s.myScore.text.trim());
              final opp = int.tryParse(s.opponentScore.text.trim());
              if (my == null || opp == null) {
                setState(() => _error = 'Please fill in every ${widget.unitLabel.toLowerCase()} score.');
                return;
              }
              if (my == opp) {
                setState(() => _error = 'A ${widget.unitLabel.toLowerCase()} cannot end in a tie.');
                return;
              }
              setScores.add({'me': my, 'opponent': opp});
              totalMy += my;
              totalOpp += opp;
              if (my > opp) {
                setsWonByMe++;
              } else {
                setsWonByOpp++;
              }
            }
            if (setsWonByMe == setsWonByOpp) {
              setState(() => _error = 'The match needs an overall winner.');
              return;
            }
            Navigator.pop(context, {
              'myUnits': totalMy,
              'opponentUnits': totalOpp,
              'iWon': setsWonByMe > setsWonByOpp,
              'setScores': setScores,
              if (_photoUrl != null) 'photoUrl': _photoUrl,
            });
          },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

class _HostReportSetsDialog extends StatefulWidget {
  final String player1Name;
  final String player2Name;
  final String title;
  final String unitLabel;
  final List<Map<String, int>>? initialSets;
  // GAP-17 — seeds the photo preview on an edit path; null on a fresh
  // report. See MatchPhotoPicker for why there's no "remove" affordance.
  final String? initialPhotoUrl;

  const _HostReportSetsDialog({
    required this.player1Name,
    required this.player2Name,
    this.title = 'Enter Score',
    this.unitLabel = 'Set',
    this.initialSets,
    this.initialPhotoUrl,
  });

  @override
  State<_HostReportSetsDialog> createState() => _HostReportSetsDialogState();
}

class _HostReportSetsDialogState extends State<_HostReportSetsDialog> {
  static const int _maxSets = 7;
  late List<_SetScore> _sets;
  String? _error;
  String? _photoUrl;
  bool _isWalkover = false;
  bool? _walkoverWinnerIsP1;

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
            CheckboxListTile(
              value: _isWalkover,
              onChanged: (v) => setState(() {
                _isWalkover = v ?? false;
                _error = null;
              }),
              title: const Text('Walkover (opponent didn\'t show)'),
              subtitle: const Text('Awards the win with no set scores and no rating change.'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            if (_isWalkover) ...[
              RadioListTile<bool>(
                value: true,
                groupValue: _walkoverWinnerIsP1,
                onChanged: (v) => setState(() => _walkoverWinnerIsP1 = v),
                title: Text('${widget.player1Name} wins'),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              RadioListTile<bool>(
                value: false,
                groupValue: _walkoverWinnerIsP1,
                onChanged: (v) => setState(() => _walkoverWinnerIsP1 = v),
                title: Text('${widget.player2Name} wins'),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ] else ...[
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
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(3),
                          ],
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
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(3),
                          ],
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
                          tooltip: 'Remove ${widget.unitLabel} ${index + 1}',
                          onPressed: () => setState(() => _sets.removeAt(index)),
                        ),
                    ],
                  ),
                );
              }),
              if (_sets.length < _maxSets)
                TextButton.icon(
                  onPressed: () => setState(() => _sets.add(_SetScore())),
                  icon: const Icon(Icons.add),
                  label: Text('Add ${widget.unitLabel}'),
                ),
            ],
            const SizedBox(height: 12),
            MatchPhotoPicker(
              initialPhotoUrl: widget.initialPhotoUrl,
              onChanged: (dataUri) => _photoUrl = dataUri,
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
            if (_isWalkover) {
              if (_walkoverWinnerIsP1 == null) {
                setState(() => _error = 'Please choose who won.');
                return;
              }
              Navigator.pop(context, {
                'isWalkover': true,
                'player1Won': _walkoverWinnerIsP1,
                if (_photoUrl != null) 'photoUrl': _photoUrl,
              });
              return;
            }

            int totalP1 = 0, totalP2 = 0, setsWonByP1 = 0, setsWonByP2 = 0;
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
              if (_photoUrl != null) 'photoUrl': _photoUrl,
            });
          },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

class _EditFixtureDialog extends StatefulWidget {
  final String format;
  final String sport;
  final List<dynamic> members;
  final int? initialPlayer1Id;
  final int? initialPlayer1PartnerId;
  final int? initialPlayer2Id;
  final int? initialPlayer2PartnerId;
  final String? initialScheduledTime;
  final String? initialVenue;

  const _EditFixtureDialog({
    required this.format,
    required this.sport,
    required this.members,
    this.initialPlayer1Id,
    this.initialPlayer1PartnerId,
    this.initialPlayer2Id,
    this.initialPlayer2PartnerId,
    this.initialScheduledTime,
    this.initialVenue,
  });

  @override
  State<_EditFixtureDialog> createState() => _EditFixtureDialogState();
}

class _EditFixtureDialogState extends State<_EditFixtureDialog> {
  int? _player1Id;
  int? _player1PartnerId;
  int? _player2Id;
  int? _player2PartnerId;
  DateTime? _scheduledDateTime;
  final TextEditingController _venueController = TextEditingController();
  String? _error;

  bool get _isDoubles => widget.format == 'doubles';

  @override
  void initState() {
    super.initState();
    _player1Id = widget.initialPlayer1Id;
    _player1PartnerId = widget.initialPlayer1PartnerId;
    _player2Id = widget.initialPlayer2Id;
    _player2PartnerId = widget.initialPlayer2PartnerId;
    _venueController.text = widget.initialVenue ?? '';
    if (widget.initialScheduledTime != null) {
      _scheduledDateTime = DateTime.tryParse(
        widget.initialScheduledTime!,
      )?.toLocal();
    }
  }

  @override
  void dispose() {
    _venueController.dispose();
    super.dispose();
  }

  List<DropdownMenuItem<int>> _items() {
    return widget.members
        .map<DropdownMenuItem<int>>(
          (m) => DropdownMenuItem(
            value: m['id'] as int,
            child: Text(
              '${m['username']} (${formatRating(widget.sport, m['rating'])})${m['is_guest'] == true ? ' · Guest' : ''}',
            ),
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
            if (_isDoubles) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _player1PartnerId,
                decoration: const InputDecoration(
                  labelText: 'Player 1 Partner',
                  isDense: true,
                ),
                items: _items(),
                onChanged: (v) => setState(() => _player1PartnerId = v),
              ),
            ],
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
            if (_isDoubles) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _player2PartnerId,
                decoration: const InputDecoration(
                  labelText: 'Player 2 Partner',
                  isDense: true,
                ),
                items: _items(),
                onChanged: (v) => setState(() => _player2PartnerId = v),
              ),
            ],
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
            const SizedBox(height: 10),
            TextField(
              controller: _venueController,
              decoration: const InputDecoration(
                labelText: 'Venue (optional)',
                prefixIcon: Icon(Icons.place_outlined),
                isDense: true,
              ),
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
            final ids = [
              _player1Id,
              _player2Id,
              if (_isDoubles) _player1PartnerId,
              if (_isDoubles) _player2PartnerId,
            ];
            if (ids.contains(null)) {
              setState(() => _error = 'Please select every player slot.');
              return;
            }
            if (ids.toSet().length != ids.length) {
              setState(() => _error = 'The same player can\'t appear in more than one slot.');
              return;
            }
            Navigator.pop(context, {
              'player1Id': _player1Id,
              'player1PartnerId': _player1PartnerId,
              'player2Id': _player2Id,
              'player2PartnerId': _player2PartnerId,
              'scheduledTime': _scheduledDateTime?.toIso8601String(),
              'venue': _venueController.text.trim().isEmpty
                  ? null
                  : _venueController.text.trim(),
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// Trimmed version of _EditFixtureDialog for knockout matches — no player
// dropdowns, since bracket slots are filled by advanceWinner, not manually.
class _EditPlayoffScheduleDialog extends StatefulWidget {
  final dynamic initialScheduledTime;
  final String? initialVenue;

  const _EditPlayoffScheduleDialog({
    this.initialScheduledTime,
    this.initialVenue,
  });

  @override
  State<_EditPlayoffScheduleDialog> createState() =>
      _EditPlayoffScheduleDialogState();
}

class _EditPlayoffScheduleDialogState
    extends State<_EditPlayoffScheduleDialog> {
  DateTime? _scheduledDateTime;
  final TextEditingController _venueController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _venueController.text = widget.initialVenue ?? '';
    if (widget.initialScheduledTime != null) {
      _scheduledDateTime = DateTime.tryParse(
        widget.initialScheduledTime.toString(),
      )?.toLocal();
    }
  }

  @override
  void dispose() {
    _venueController.dispose();
    super.dispose();
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
      title: const Text('Edit Schedule'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            const SizedBox(height: 10),
            TextField(
              controller: _venueController,
              decoration: const InputDecoration(
                labelText: 'Venue (optional)',
                prefixIcon: Icon(Icons.place_outlined),
                isDense: true,
              ),
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
            Navigator.pop(context, {
              'scheduledTime': _scheduledDateTime?.toIso8601String(),
              'venue': _venueController.text.trim().isEmpty
                  ? null
                  : _venueController.text.trim(),
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
