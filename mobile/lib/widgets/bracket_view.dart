// bracket_view.dart
// The actual bracket UI (fetch, standings-free "rounds" list, report/confirm/
// edit-score dialogs) — extracted out of playoffs_screen.dart so it can be
// embedded directly inline wherever a bracket needs to appear, instead of
// always being its own separate screen. A knockout-format group renders
// this straight inside its own tab in groups_overview_screen.dart; the
// whole-tournament "Playoffs" feature (playoffs_screen.dart) wraps it in a
// Scaffold/AppBar, since that one still needs its own generate/cancel
// actions and navigation entry point.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../config.dart';
import 'match_photo_picker.dart';
import 'match_photo_thumbnail.dart';
import 'team_name_row.dart';

class BracketView extends StatefulWidget {
  final int leagueId;
  final bool isHost;
  final String format;
  // Set when this is one knockout-format group's bracket within a Groups
  // tournament, rather than a whole-tournament knockout league. A group's
  // bracket is generated when the host locks that group (see
  // group_management_screen.dart) — there's no separate generate/cancel
  // step here the way there is for a whole-tournament knockout league.
  final int? groupId;
  final bool groupLocked;
  // Lets an optional wrapping Scaffold (playoffs_screen.dart) react to
  // bracket state for its own "cancel playoffs" AppBar action — this widget
  // has no AppBar/Scaffold of its own, so it can't show that action itself.
  final void Function(bool hasBracket)? onBracketChanged;
  final void Function(bool cancelling)? onCancellingChanged;

  const BracketView({
    super.key,
    required this.leagueId,
    required this.isHost,
    this.format = 'singles',
    this.groupId,
    this.groupLocked = false,
    this.onBracketChanged,
    this.onCancellingChanged,
  });

  @override
  State<BracketView> createState() => BracketViewState();
}

class BracketViewState extends State<BracketView> {
  List<dynamic> _bracket = [];
  int? _currentUserId;
  bool _loading = true;
  String? _error;
  bool _generating = false;
  bool _hostEntersScores = false;
  String _sport = '';

  bool get _isDoubles => widget.format == 'doubles';

  // Tennis is scored in "Sets"; everything else in this app is "Games".
  String get _unitLabel => _sport == 'tennis' ? 'Set' : 'Game';

  String _teamName(dynamic m, {required bool isSideOne}) {
    final username = isSideOne ? m['player1_username'] : m['player2_username'];
    final partnerUsername = isSideOne
        ? m['player1_partner_username']
        : m['player2_partner_username'];
    if (username == null) return 'TBD';
    if (_isDoubles && partnerUsername != null) {
      return '$username & $partnerUsername';
    }
    return username;
  }

  @override
  void initState() {
    super.initState();
    loadBracket();
  }

  Future<void> loadBracket() async {
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
      if (leagueRes.statusCode == 200) {
        _hostEntersScores = leagueData['league']['host_enters_scores'] == true;
        _sport = leagueData['league']['sport'] ?? '';
      }

      final bracketPath = widget.groupId != null
          ? '$baseApiUrl/playoffs/${widget.leagueId}/group/${widget.groupId}'
          : '$baseApiUrl/playoffs/${widget.leagueId}';
      final response = await http.get(
        Uri.parse(bracketPath),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        setState(() => _bracket = data['bracket']);
        widget.onBracketChanged?.call(_bracket.isNotEmpty);
      } else {
        setState(() => _error = data['error'] ?? 'Could not load bracket.');
      }
    } catch (err) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> generateBracket(
    int qualifierCount, {
    bool force = false,
  }) async {
    HapticFeedback.lightImpact();
    setState(() => _generating = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.post(
        Uri.parse('$baseApiUrl/playoffs/${widget.leagueId}/generate'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'qualifierCount': qualifierCount, 'force': force}),
      );
      final data = jsonDecode(response.body);

      if (!mounted) return;
      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bracket generated!'),
            backgroundColor: AppColors.success,
          ),
        );
        loadBracket();
      } else if (data['incompleteMatches'] != null) {
        setState(() => _generating = false);
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            title: const Text('Season not finished yet'),
            content: Text(
              '${data['error']} Starting playoffs now means those matches will never be played. Continue anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Start Playoffs Anyway',
                  style: TextStyle(color: AppColors.danger),
                ),
              ),
            ],
          ),
        );
        if (proceed == true) {
          await generateBracket(qualifierCount, force: true);
        }
        return;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not generate bracket.'),
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

  Future<void> confirmCancelPlayoffs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('Cancel playoffs?'),
        content: const Text(
          'This removes the entire bracket, including any confirmed results. You can start a new bracket afterward once the regular season is actually finished.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep bracket'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Cancel playoffs',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    HapticFeedback.mediumImpact();
    widget.onCancellingChanged?.call(true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final response = await http.delete(
        Uri.parse('$baseApiUrl/playoffs/${widget.leagueId}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);

      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Playoff bracket removed.'),
            backgroundColor: AppColors.success,
          ),
        );
        loadBracket();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not remove bracket.'),
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
      widget.onCancellingChanged?.call(false);
    }
  }

  Future<void> _reportMatch(dynamic m) async {
    final iAmSideOne =
        m['player1_id'] == _currentUserId ||
        m['player1_partner_id'] == _currentUserId;
    final opponentName = _teamName(m, isSideOne: !iAmSideOne);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _PlayoffReportDialog(
        unitLabel: _unitLabel,
        opponentLabel: opponentName,
      ),
    );
    if (result == null) return;

    HapticFeedback.lightImpact();
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.post(
        Uri.parse('$baseApiUrl/playoffs/match/${m['id']}/report'),
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
        loadBracket();
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

  Future<void> _editMyReport(dynamic m) async {
    List<Map<String, int>>? initialSets;
    try {
      if (m['set_scores'] != null) {
        final List raw = jsonDecode(m['set_scores']);
        initialSets = raw
            .map<Map<String, int>>(
              (s) => {'me': s['me'] as int, 'opponent': s['opponent'] as int},
            )
            .toList();
      }
    } catch (err) {
      initialSets = null;
    }

    final iAmSideOne =
        m['player1_id'] == _currentUserId ||
        m['player1_partner_id'] == _currentUserId;
    final opponentName = _teamName(m, isSideOne: !iAmSideOne);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _PlayoffReportDialog(
        title: 'Edit My Report',
        unitLabel: _unitLabel,
        opponentLabel: opponentName,
        initialSets: initialSets,
        initialPhotoUrl: m['photo_url'],
      ),
    );
    if (result == null) return;

    HapticFeedback.lightImpact();
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.put(
        Uri.parse('$baseApiUrl/playoffs/match/${m['id']}/edit-report'),
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
            content: Text('Report updated.'),
            backgroundColor: AppColors.success,
          ),
        );
        loadBracket();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not update report.'),
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

  Future<void> _hostReportMatch(
    int matchId,
    String player1Name,
    String player2Name,
  ) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _HostPlayoffReportDialog(
        player1Name: player1Name,
        player2Name: player2Name,
        unitLabel: _unitLabel,
      ),
    );
    if (result == null) return;

    HapticFeedback.lightImpact();
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
        loadBracket();
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

  Future<void> _hostEditScore(dynamic m) async {
    final p1Name = _teamName(m, isSideOne: true);
    final p2Name = _teamName(m, isSideOne: false);

    List<Map<String, int>>? initialSets;
    try {
      if (m['set_scores'] != null) {
        final List raw = jsonDecode(m['set_scores']);
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
      builder: (ctx) => _HostPlayoffReportDialog(
        player1Name: p1Name,
        player2Name: p2Name,
        title: 'Edit Score',
        unitLabel: _unitLabel,
        initialSets: initialSets,
        initialPhotoUrl: m['photo_url'],
      ),
    );
    if (result == null) return;

    HapticFeedback.lightImpact();
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.put(
        Uri.parse('$baseApiUrl/playoffs/match/${m['id']}/edit-score'),
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
            content: Text(data['warning'] ?? 'Score updated.'),
            backgroundColor: data['warning'] != null
                ? AppColors.warning
                : AppColors.success,
          ),
        );
        loadBracket();
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

  Future<void> _confirmMatch(int matchId) async {
    HapticFeedback.lightImpact();
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
        loadBracket();
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

  Future<void> _rejectMatch(int matchId) async {
    HapticFeedback.mediumImpact();
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
        loadBracket();
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(onPressed: loadBracket, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    return _bracket.isEmpty ? _buildEmptyState() : _buildBracket();
  }

  Widget _buildEmptyState() {
    final unit = _isDoubles ? 'teams' : 'players';

    if (widget.groupId != null) {
      // A group's bracket is generated when the host locks that group, from
      // whoever is already in it — there's no separate qualifier-count step
      // here the way there is for a whole-tournament knockout league.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            widget.groupLocked
                ? 'No bracket yet.'
                : (widget.isHost
                      ? 'Lock this group from Manage Groups to generate its bracket.'
                      : "The host hasn't locked this group yet."),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.isHost
                  ? 'No playoff bracket yet.'
                  : "The host hasn't started playoffs yet.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (widget.isHost) ...[
              const SizedBox(height: 16),
              Text(
                'Choose bracket size:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_isDoubles) ...[
                const SizedBox(height: 4),
                Text(
                  'Teams are formed from confirmed partnerships, seeded by combined tournament points (rating breaks ties).',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    onPressed: _generating ? null : () => generateBracket(4),
                    child: Text('Top 4 $unit'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _generating ? null : () => generateBracket(8),
                    child: Text('Top 8 $unit'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBracket() {
    final cardColor = Theme.of(context).cardColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    final subtleTextColor = isDark
        ? Colors.grey.shade400
        : Colors.grey.shade600;
    final primaryTextColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark;

    final Map<int, List<dynamic>> rounds = {};
    for (final m in _bracket) {
      rounds.putIfAbsent(m['round_number'], () => []).add(m);
    }
    final totalRounds = rounds.keys.reduce((a, b) => a > b ? a : b);

    return RefreshIndicator(
      onRefresh: loadBracket,
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
                Text(roundName, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                ...entry.value.map((m) {
                  final player1Name = _teamName(m, isSideOne: true);
                  final player2Name = _teamName(m, isSideOne: false);
                  final isReady = m['status'] == 'ready';
                  final isReported = m['status'] == 'reported';
                  final isConfirmed = m['status'] == 'confirmed';
                  final team1Won =
                      isConfirmed && m['winner_id'] == m['player1_id'];
                  final team2Won =
                      isConfirmed && m['winner_id'] == m['player2_id'];
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
                      color: cardColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isConfirmed
                            ? AppColors.success.withValues(alpha: 0.4)
                            : borderColor,
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
                                      playerId: m['player1_id'],
                                      playerName:
                                          m['player1_username'] ?? 'TBD',
                                      partnerId: m['player1_partner_id'],
                                      partnerName:
                                          m['player1_partner_username'],
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
                                  Text(
                                    '  vs  ',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: subtleTextColor,
                                    ),
                                  ),
                                  Flexible(
                                    child: TeamNameRow(
                                      playerId: m['player2_id'],
                                      playerName:
                                          m['player2_username'] ?? 'TBD',
                                      partnerId: m['player2_partner_id'],
                                      partnerName:
                                          m['player2_partner_username'],
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
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isConfirmed
                                    ? AppColors.success.withValues(alpha: 0.1)
                                    : AppColors.warning.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isConfirmed ? 'Done' : 'Pending',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: isConfirmed
                                      ? AppColors.success
                                      : AppColors.warning,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (m['set_scores'] != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _formatSetScores(m['set_scores']),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: subtleTextColor,
                                  ),
                                ),
                              ),
                              if (m['photo_url'] != null)
                                MatchPhotoThumbnail(
                                  photoUrl: m['photo_url'],
                                  size: 28,
                                ),
                            ],
                          ),
                        ],
                        if (_hostEntersScores && widget.isHost && isReady) ...[
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _hostReportMatch(
                                m['id'],
                                player1Name,
                                player2Name,
                              ),
                              icon: const Icon(Icons.sports_score, size: 15),
                              label: const Text(
                                'Enter Score',
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
                        if (!_hostEntersScores && isReady && involvesMe) ...[
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _reportMatch(m),
                              icon: const Icon(Icons.sports_score, size: 15),
                              label: const Text(
                                'Report Result',
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
                        if (!_hostEntersScores &&
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
                                  onPressed: () => _rejectMatch(m['id']),
                                  child: const Text(
                                    'Reject',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => _confirmMatch(m['id']),
                                  child: const Text(
                                    'Confirm',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (!_hostEntersScores &&
                            isReported &&
                            reportedByMe) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 6, bottom: 6),
                            child: Text(
                              'Waiting for opponent to confirm...',
                              style: TextStyle(
                                fontSize: 11,
                                color: subtleTextColor,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _editMyReport(m),
                            icon: const Icon(Icons.edit_outlined, size: 15),
                            label: const Text(
                              'Edit My Report',
                              style: TextStyle(fontSize: 12),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                        if (widget.isHost && isConfirmed) ...[
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _hostEditScore(m),
                              icon: const Icon(Icons.edit_outlined, size: 15),
                              label: const Text(
                                'Edit Score',
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
}

class _PlayoffReportDialog extends StatefulWidget {
  final String title;
  final String unitLabel;
  final String opponentLabel;
  final List<Map<String, int>>? initialSets;
  // GAP-17 — seeds the photo preview on an edit path; null on a fresh
  // report. See MatchPhotoPicker for why there's no "remove" affordance.
  final String? initialPhotoUrl;

  const _PlayoffReportDialog({
    this.title = 'Report Result',
    this.unitLabel = 'Set',
    this.opponentLabel = 'Opponent',
    this.initialSets,
    this.initialPhotoUrl,
  });

  @override
  State<_PlayoffReportDialog> createState() => _PlayoffReportDialogState();
}

class _SetScore {
  final TextEditingController myScore = TextEditingController();
  final TextEditingController opponentScore = TextEditingController();
}

class _PlayoffReportDialogState extends State<_PlayoffReportDialog> {
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
                        decoration: InputDecoration(
                          labelText: widget.opponentLabel,
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
            int totalMy = 0;
            int totalOpp = 0;
            int setsWonByMe = 0;
            int setsWonByOpp = 0;
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

class _HostPlayoffReportDialog extends StatefulWidget {
  final String player1Name;
  final String player2Name;
  final String title;
  final String unitLabel;
  final List<Map<String, int>>? initialSets;
  // GAP-17 — seeds the photo preview on an edit path; null on a fresh
  // report. See MatchPhotoPicker for why there's no "remove" affordance.
  final String? initialPhotoUrl;

  const _HostPlayoffReportDialog({
    required this.player1Name,
    required this.player2Name,
    this.title = 'Enter Score',
    this.unitLabel = 'Set',
    this.initialSets,
    this.initialPhotoUrl,
  });

  @override
  State<_HostPlayoffReportDialog> createState() =>
      _HostPlayoffReportDialogState();
}

class _HostPlayoffReportDialogState extends State<_HostPlayoffReportDialog> {
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
                        tooltip: 'Remove ${widget.unitLabel} ${index + 1}',
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
              if (_photoUrl != null) 'photoUrl': _photoUrl,
            });
          },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
