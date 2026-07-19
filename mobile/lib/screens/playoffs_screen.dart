// playoffs_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../config.dart';

class PlayoffsScreen extends StatefulWidget {
  final int leagueId;
  final bool isHost;

  const PlayoffsScreen({
    super.key,
    required this.leagueId,
    required this.isHost,
  });

  @override
  State<PlayoffsScreen> createState() => _PlayoffsScreenState();
}

class _PlayoffsScreenState extends State<PlayoffsScreen> {
  List<dynamic> _bracket = [];
  int? _currentUserId;
  bool _loading = true;
  bool _generating = false;
  bool _hostEntersScores = false;

  @override
  void initState() {
    super.initState();
    _loadBracket();
  }

  Future<void> _loadBracket() async {
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
        _hostEntersScores = leagueData['league']['host_enters_scores'] == true;
      }

      final response = await http.get(
        Uri.parse('$baseApiUrl/playoffs/${widget.leagueId}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        setState(() => _bracket = data['bracket']);
      }
    } catch (err) {
      // fail silently
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _generateBracket(int qualifierCount) async {
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
        body: jsonEncode({'qualifierCount': qualifierCount}),
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
        _loadBracket();
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

  Future<void> _reportMatch(int matchId) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _PlayoffReportDialog(),
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
        _loadBracket();
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
      ),
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
        _loadBracket();
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

  Future<void> _confirmMatch(int matchId) async {
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
        _loadBracket();
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
        _loadBracket();
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
    return Scaffold(
      appBar: AppBar(title: const Text('Playoffs')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _bracket.isEmpty
          ? _buildEmptyState()
          : _buildBracket(),
    );
  }

  Widget _buildEmptyState() {
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
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    onPressed: _generating ? null : () => _generateBracket(4),
                    child: const Text('Top 4'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _generating ? null : () => _generateBracket(8),
                    child: const Text('Top 8'),
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
    final Map<int, List<dynamic>> rounds = {};
    for (final m in _bracket) {
      rounds.putIfAbsent(m['round_number'], () => []).add(m);
    }
    final totalRounds = rounds.keys.reduce((a, b) => a > b ? a : b);

    return RefreshIndicator(
      onRefresh: _loadBracket,
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
                  final player1Name = m['player1_username'] ?? 'TBD';
                  final player2Name = m['player2_username'] ?? 'TBD';
                  final isReady = m['status'] == 'ready';
                  final isReported = m['status'] == 'reported';
                  final isConfirmed = m['status'] == 'confirmed';
                  final iAmPlayer1 = m['player1_id'] == _currentUserId;
                  final iAmPlayer2 = m['player2_id'] == _currentUserId;
                  final involvesMe = iAmPlayer1 || iAmPlayer2;
                  final reportedByMe = m['reported_by'] == _currentUserId;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
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
                                '$player1Name  vs  $player2Name',
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
                                'Winner: ${m['winner_id'] == m['player1_id'] ? player1Name : player2Name}',
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

                        // Host-enters-scores mode: only the host sees an entry button.
                        if (_hostEntersScores && widget.isHost && isReady) ...[
                          const SizedBox(height: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            onPressed: () => _hostReportMatch(
                              m['id'],
                              player1Name,
                              player2Name,
                            ),
                            child: const Text(
                              'Enter Score',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],

                        // Normal mode: either player self-reports.
                        if (!_hostEntersScores && isReady && involvesMe) ...[
                          const SizedBox(height: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            onPressed: () => _reportMatch(m['id']),
                            child: const Text(
                              'Report Result',
                              style: TextStyle(fontSize: 12),
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
                        if (!_hostEntersScores && isReported && reportedByMe)
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
}

class _SetScore {
  final TextEditingController player1Score = TextEditingController();
  final TextEditingController player2Score = TextEditingController();
}

// Self-report dialog (normal mode) — asks from "your" perspective.
class _PlayoffReportDialog extends StatefulWidget {
  @override
  State<_PlayoffReportDialog> createState() => _PlayoffReportDialogState();
}

class _PlayoffReportDialogState extends State<_PlayoffReportDialog> {
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
                        controller: set.player1Score,
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
                        controller: set.player2Score,
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
            int totalMy = 0;
            int totalOpp = 0;
            int setsWonByMe = 0;
            int setsWonByOpp = 0;
            final List<Map<String, int>> setScores = [];

            for (final s in _sets) {
              final my = int.tryParse(s.player1Score.text.trim());
              final opp = int.tryParse(s.player2Score.text.trim());
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

// Host-entry dialog — asks explicitly for Player1's and Player2's scores by name.
class _HostPlayoffReportDialog extends StatefulWidget {
  final String player1Name;
  final String player2Name;

  const _HostPlayoffReportDialog({
    required this.player1Name,
    required this.player2Name,
  });

  @override
  State<_HostPlayoffReportDialog> createState() =>
      _HostPlayoffReportDialogState();
}

class _HostPlayoffReportDialogState extends State<_HostPlayoffReportDialog> {
  final List<_SetScore> _sets = [_SetScore()];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: const Text('Enter Score'),
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
                        controller: set.player1Score,
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
                        controller: set.player2Score,
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
            int totalP1 = 0;
            int totalP2 = 0;
            int setsWonByP1 = 0;
            int setsWonByP2 = 0;
            final List<Map<String, int>> setScores = [];

            for (final s in _sets) {
              final p1 = int.tryParse(s.player1Score.text.trim());
              final p2 = int.tryParse(s.player2Score.text.trim());
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
