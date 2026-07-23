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
import 'regenerate_schedule_dialog.dart';
import 'add_players_screen.dart';
import 'add_manual_match_screen.dart';
import 'edit_league_screen.dart';
import 'player_profile_screen.dart';

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
  List<dynamic> _bracket = [];
  int? _currentUserId;
  bool _loading = true;
  bool _deleting = false;
  bool _leaving = false;
  bool _joining = false;
  bool _generating = false;
  bool _regenerating = false;
  String? _error;

  bool get _isMember =>
      _currentUserId != null &&
      _leaderboard.any((p) => p['id'] == _currentUserId);
  bool get _isKnockout =>
      _league != null && _league!['schedule_type'] == 'knockout';
  bool get _isCustom =>
      _league != null && _league!['schedule_type'] == 'custom';
  bool get _isLeagueStyle => !_isKnockout && !_isCustom;
  bool get _hasConfirmedMatches {
    if (_isKnockout) {
      return _bracket.any((m) => m['status'] == 'confirmed');
    }
    return _schedule.any((f) => f['match_status'] == 'confirmed');
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
          () => _error = leagueData['error'] ?? 'Could not load tournament.',
        );
        return;
      }
      setState(() {
        _league = leagueData['league'];
        _leaderboard = leagueData['leaderboard'];
      });

      if (_isKnockout) {
        final bracketRes = await http.get(
          Uri.parse('$baseApiUrl/playoffs/${widget.leagueId}'),
          headers: {'Authorization': 'Bearer $token'},
        );
        final bracketData = jsonDecode(bracketRes.body);
        if (bracketRes.statusCode == 200) {
          setState(() => _bracket = bracketData['bracket']);
        }
      } else {
        final scheduleRes = await http.get(
          Uri.parse('$baseApiUrl/leagues/${widget.leagueId}/schedule'),
          headers: {'Authorization': 'Bearer $token'},
        );
        final scheduleData = jsonDecode(scheduleRes.body);
        if (scheduleRes.statusCode == 200) {
          setState(() => _schedule = scheduleData['schedule']);
        }
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
            content: Text('Joined tournament!'),
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
            content: Text(data['message'] ?? 'Schedule generated.'),
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

  Future<void> _regenerateSchedule() async {
    final result = await showDialog<RegenerateScheduleResult>(
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('Confirm regeneration?'),
        content: const Text(
          'This replaces the current fixture list. Confirmed results stay in history, but any pending unconfirmed reports will be discarded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _regenerating = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.post(
        Uri.parse('$baseApiUrl/leagues/${widget.leagueId}/regenerate-schedule'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'scheduleType': result.scheduleType,
          'matchesPerPlayer': result.matchesPerPlayer,
        }),
      );
      final data = jsonDecode(response.body);

      if (!mounted) return;
      if (response.statusCode == 201 || response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Schedule regenerated.'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadAll();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not regenerate schedule.'),
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
            content: Text(data['error'] ?? 'Could not delete tournament.'),
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
            content: Text(data['error'] ?? 'Could not leave tournament.'),
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

  Future<void> _reportKnockoutMatch(int matchId) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => const _SelfReportSetsDialog(),
    );
    if (result == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final response = await http.post(
        Uri.parse('$baseApiUrl/playoffs/match/$matchId/report'),
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
          const SnackBar(
            content: Text('Result reported!'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadAll();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not report.'),
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
      builder: (ctx) =>
          _HostReportSetsDialog(player1Name: p1Name, player2Name: p2Name),
    );
    if (result == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final response = await http.post(
        Uri.parse('$baseApiUrl/playoffs/match/$matchId/report-as-host'),
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
          const SnackBar(
            content: Text('Match confirmed!'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadAll();
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

  Future<void> _confirmKnockoutMatch(int matchId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final response = await http.post(
        Uri.parse('$baseApiUrl/playoffs/match/$matchId/confirm'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 200) {
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
            content: Text(data['error'] ?? 'Could not confirm.'),
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
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final response = await http.post(
        Uri.parse('$baseApiUrl/playoffs/match/$matchId/reject'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 200) {
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
            content: Text(data['error'] ?? 'Could not reject.'),
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
        _loadAll();
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

  Future<void> _openEditFixtureDialog(dynamic f) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _EditFixtureDialog(
        format: _league!['format'],
        members: _leaderboard,
        initialPlayer1Id: f['player1_id'],
        initialPlayer1PartnerId: f['player1_partner_id'],
        initialPlayer2Id: f['player2_id'],
        initialPlayer2PartnerId: f['player2_partner_id'],
        initialScheduledTime: f['scheduled_time'],
      ),
    );
    if (result == null) return;

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
          'player1PartnerId': result['player1PartnerId'],
          'player2Id': result['player2Id'],
          'player2PartnerId': result['player2PartnerId'],
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
        _loadAll();
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
        initialSets: initialSets,
      ),
    );
    if (result == null) return;

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
        _loadAll();
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
        _loadAll();
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

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final response = await http.delete(
        Uri.parse('$baseApiUrl/leagues/${widget.leagueId}/members/$userId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 200) {
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
            content: Text(data['error'] ?? 'Could not remove player.'),
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
      if (p['id'] == playerId) return '${p['rating']}';
    }
    return null;
  }

  Widget? _buildActionButton(bool isHost) {
    if (_isKnockout) return null;

    final hostEntersScores = _league!['host_enters_scores'] == true;

    if (_isCustom && isHost) {
      return FloatingActionButton.extended(
        onPressed: () async {
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
                members: _leaderboard,
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
        appBar: AppBar(title: const Text('Tournament')),
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
                      builder: (_) =>
                          AddPlayersScreen(leagueId: widget.leagueId),
                    ),
                  );
                  if (result != null) _loadAll();
                },
              ),
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

  Widget _buildLeaderboardTab(bool isHost) {
    final academyName = _league!['academy_name'];
    final hostUsername = _league!['host_username'];
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
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _league!['name'],
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: primaryTextColor,
                  ),
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
                  '${formatDateOnly(_league!['season_start'])} to ${formatDateOnly(_league!['season_end'])} · ${_leaderboard.length} players · ${_league!['format']} · ${_league!['gender_category'] == 'mens' ? "Men's" : "Women's"}',
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
                  Row(
                    children: [
                      const Icon(
                        Icons.phone_outlined,
                        size: 14,
                        color: AppColors.textGrey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _league!['host_phone'],
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                ],
                if (_isLeagueStyle) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Ranked by tournament points (win = 2, +1 for a dominant win)',
                    style: TextStyle(
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
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.key_outlined,
                          size: 16,
                          color: AppColors.textDark,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Join code: ${_league!['join_code']}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                label: const Text('Join Tournament'),
              ),
            )
          else if (!isHost)
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
          if (_isMember && _league!['format'] == 'singles' && _isLeagueStyle)
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
          if (isHost &&
              !_isCustom &&
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
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Material(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 0,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PlayerProfileScreen(userId: player['id']),
                        ),
                      );
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
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (_isLeagueStyle)
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

  Widget _buildKnockoutTab(bool isHost) {
    if (!_isMember && !isHost) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Join this tournament to see the bracket.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    if (_bracket.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            isHost
                ? 'No bracket yet. Generate one from the Leaderboard tab.'
                : "The host hasn't generated the bracket yet.",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
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
                  final p1 = m['player1_username'] ?? 'TBD';
                  final p2 = m['player2_username'] ?? 'TBD';
                  final isReady = m['status'] == 'ready';
                  final isReported = m['status'] == 'reported';
                  final isConfirmed = m['status'] == 'confirmed';
                  final involvesMe =
                      m['player1_id'] == _currentUserId ||
                      m['player2_id'] == _currentUserId;
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
                        if (m['set_scores'] != null) ...[
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Join this tournament to see the schedule.',
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
            _isCustom
                ? (isHost
                      ? 'No matches added yet. Use "Add Match" below.'
                      : "The host hasn't added any matches yet.")
                : (isHost
                      ? 'No schedule yet. Generate one from the Leaderboard tab.'
                      : "The host hasn't generated a schedule yet."),
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

    final showTierHeadings = _league!['schedule_type'] == 'round_robin';

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isHost && !_isCustom)
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
                  if (showTierHeadings) ...[
                    Text(
                      'Tier ${entry.key}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                  ],
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

  Widget _buildMyMatchesTab(bool isHost) {
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
                m['player2_id'] == _currentUserId,
          )
          .toList();
      if (myMatches.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No bracket matches for you yet.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: myMatches.map((m) {
          final p1 = m['player1_username'] ?? 'TBD';
          final p2 = m['player2_username'] ?? 'TBD';
          final isConfirmed = m['status'] == 'confirmed';
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$p1 vs $p2',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Text(
                  isConfirmed ? 'Done' : m['status'],
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
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
    final team1 = isDoubles
        ? '${f['player1_username']} & ${f['player1_partner_username']}'
        : (p1Rating != null
              ? '${f['player1_username']} ($p1Rating)'
              : f['player1_username']);
    final team2 = isDoubles
        ? '${f['player2_username']} & ${f['player2_partner_username']}'
        : (p2Rating != null
              ? '${f['player2_username']} ($p2Rating)'
              : f['player2_username']);
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
                                    : primaryTextColor,
                              ),
                            ),
                            TextSpan(
                              text: '  vs  ',
                              style: TextStyle(
                                fontSize: 13,
                                color: subtleVsColor,
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
                                    : primaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Text(
                        '$team1 vs $team2',
                        style: TextStyle(fontSize: 13, color: primaryTextColor),
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
                Icon(Icons.event, size: 12, color: subtleVsColor),
                const SizedBox(width: 4),
                Text(
                  _formatScheduledTime(f['scheduled_time']),
                  style: TextStyle(fontSize: 11, color: subtleVsColor),
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
  const _SelfReportSetsDialog();

  @override
  State<_SelfReportSetsDialog> createState() => _SelfReportSetsDialogState();
}

class _SelfReportSetsDialogState extends State<_SelfReportSetsDialog> {
  final List<_SetScore> _sets = [_SetScore()];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: const Text('Report Result'),
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
                          labelText: 'Set ${index + 1} — You',
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
                        decoration: const InputDecoration(
                          labelText: 'Opponent',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            TextButton.icon(
              onPressed: () => setState(() => _sets.add(_SetScore())),
              icon: const Icon(Icons.add),
              label: const Text('Add Set'),
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
              if (my == null || opp == null || my == opp) return;
              setScores.add({'me': my, 'opponent': opp});
              totalMy += my;
              totalOpp += opp;
              if (my > opp) {
                setsWonByMe++;
              } else {
                setsWonByOpp++;
              }
            }
            if (setsWonByMe == setsWonByOpp) return;
            Navigator.pop(context, {
              'myUnits': totalMy,
              'opponentUnits': totalOpp,
              'iWon': setsWonByMe > setsWonByOpp,
              'setScores': setScores,
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
  final List<Map<String, int>>? initialSets;

  const _HostReportSetsDialog({
    required this.player1Name,
    required this.player2Name,
    this.title = 'Enter Score',
    this.initialSets,
  });

  @override
  State<_HostReportSetsDialog> createState() => _HostReportSetsDialogState();
}

class _HostReportSetsDialogState extends State<_HostReportSetsDialog> {
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
                          labelText: 'Set ${index + 1} — ${widget.player1Name}',
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
                  ],
                ),
              );
            }),
            TextButton.icon(
              onPressed: () => setState(() => _sets.add(_SetScore())),
              icon: const Icon(Icons.add),
              label: const Text('Add Set'),
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
            int totalP1 = 0, totalP2 = 0, setsWonByP1 = 0, setsWonByP2 = 0;
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

class _EditFixtureDialog extends StatefulWidget {
  final String format;
  final List<dynamic> members;
  final int? initialPlayer1Id;
  final int? initialPlayer1PartnerId;
  final int? initialPlayer2Id;
  final int? initialPlayer2PartnerId;
  final String? initialScheduledTime;

  const _EditFixtureDialog({
    required this.format,
    required this.members,
    this.initialPlayer1Id,
    this.initialPlayer1PartnerId,
    this.initialPlayer2Id,
    this.initialPlayer2PartnerId,
    this.initialScheduledTime,
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

  bool get _isDoubles => widget.format == 'doubles';

  @override
  void initState() {
    super.initState();
    _player1Id = widget.initialPlayer1Id;
    _player1PartnerId = widget.initialPlayer1PartnerId;
    _player2Id = widget.initialPlayer2Id;
    _player2PartnerId = widget.initialPlayer2PartnerId;
    if (widget.initialScheduledTime != null) {
      _scheduledDateTime = DateTime.tryParse(
        widget.initialScheduledTime!,
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
            if (ids.contains(null)) return;
            if (ids.toSet().length != ids.length) return;
            Navigator.pop(context, {
              'player1Id': _player1Id,
              'player1PartnerId': _player1PartnerId,
              'player2Id': _player2Id,
              'player2PartnerId': _player2PartnerId,
              'scheduledTime': _scheduledDateTime?.toIso8601String(),
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
