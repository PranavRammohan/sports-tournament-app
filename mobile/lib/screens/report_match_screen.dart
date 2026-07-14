// report_match_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

const String apiUrl = 'http://localhost:3000/api';

class ReportMatchScreen extends StatefulWidget {
  final int leagueId;
  final String format;
  final String sport;
  final List<dynamic> members;

  const ReportMatchScreen({
    super.key,
    required this.leagueId,
    required this.format,
    required this.sport,
    required this.members,
  });

  @override
  State<ReportMatchScreen> createState() => _ReportMatchScreenState();
}

class _SetScore {
  final TextEditingController myScore = TextEditingController();
  final TextEditingController opponentScore = TextEditingController();
}

class _ReportMatchScreenState extends State<ReportMatchScreen> {
  bool _loadingFixtures = true;
  bool _scheduleExists = false;
  List<dynamic> _myPendingFixtures = [];
  int? _currentUserId;

  // Selected fixture (schedule mode) OR manually picked opponent (free mode)
  Map<String, dynamic>? _selectedFixture;
  int? _opponentId;
  int? _partnerId;
  int? _opponentPartnerId;

  final List<_SetScore> _sets = [_SetScore()];
  bool _submitting = false;

  String get _unitLabel => widget.sport == 'tennis' ? 'Set' : 'Game';

  @override
  void initState() {
    super.initState();
    _loadFixtures();
  }

  Future<void> _loadFixtures() async {
    setState(() => _loadingFixtures = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final userJson = prefs.getString('user');
      if (userJson != null) {
        _currentUserId = jsonDecode(userJson)['id'];
      }

      final response = await http.get(
        Uri.parse('$apiUrl/leagues/${widget.leagueId}/schedule'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final List allFixtures = data['schedule'];
        setState(() => _scheduleExists = allFixtures.isNotEmpty);

        final myFixtures = allFixtures.where((f) {
          final involved = [
            f['player1_id'],
            f['player1_partner_id'],
            f['player2_id'],
            f['player2_partner_id'],
          ];
          final notCompleted = f['match_status'] != 'confirmed';
          return involved.contains(_currentUserId) && notCompleted;
        }).toList();

        setState(() => _myPendingFixtures = myFixtures);
      }
    } catch (err) {
      // fall back to free mode silently
    } finally {
      setState(() => _loadingFixtures = false);
    }
  }

  void _selectFixture(Map<String, dynamic> fixture) {
    final iAmTeam1 =
        fixture['player1_id'] == _currentUserId ||
        fixture['player1_partner_id'] == _currentUserId;

    setState(() {
      _selectedFixture = fixture;
      if (iAmTeam1) {
        _opponentId = fixture['player2_id'];
        _opponentPartnerId = fixture['player2_partner_id'];
        _partnerId = fixture['player1_partner_id'] == _currentUserId
            ? fixture['player1_id']
            : fixture['player1_partner_id'];
      } else {
        _opponentId = fixture['player1_id'];
        _opponentPartnerId = fixture['player1_partner_id'];
        _partnerId = fixture['player2_partner_id'] == _currentUserId
            ? fixture['player2_id']
            : fixture['player2_partner_id'];
      }
    });
  }

  String _fixtureOpponentLabel(Map<String, dynamic> fixture) {
    final iAmTeam1 =
        fixture['player1_id'] == _currentUserId ||
        fixture['player1_partner_id'] == _currentUserId;
    if (iAmTeam1) {
      final isDoubles = fixture['player2_partner_username'] != null;
      return isDoubles
          ? '${fixture['player2_username']} & ${fixture['player2_partner_username']}'
          : fixture['player2_username'];
    } else {
      final isDoubles = fixture['player1_partner_username'] != null;
      return isDoubles
          ? '${fixture['player1_username']} & ${fixture['player1_partner_username']}'
          : fixture['player1_username'];
    }
  }

  void _addSet() {
    setState(() => _sets.add(_SetScore()));
  }

  void _removeSet(int index) {
    if (_sets.length > 1) {
      setState(() => _sets.removeAt(index));
    }
  }

  Future<void> _handleSubmit() async {
    if (_opponentId == null) {
      _showAlert('Missing info', 'Please select an opponent.');
      return;
    }
    if (widget.format == 'doubles' &&
        (_partnerId == null || _opponentPartnerId == null)) {
      _showAlert(
        'Missing info',
        'Doubles matches need both partners selected.',
      );
      return;
    }

    int totalMyUnits = 0;
    int totalOpponentUnits = 0;
    int setsWonByMe = 0;
    int setsWonByOpponent = 0;
    final List<Map<String, int>> setScores = [];

    for (final s in _sets) {
      final my = int.tryParse(s.myScore.text.trim());
      final opp = int.tryParse(s.opponentScore.text.trim());
      if (my == null || opp == null) {
        _showAlert('Missing scores', 'Please fill in every $_unitLabel score.');
        return;
      }
      if (my == opp) {
        _showAlert('Invalid score', 'A $_unitLabel cannot end in a tie.');
        return;
      }
      setScores.add({'me': my, 'opponent': opp});
      totalMyUnits += my;
      totalOpponentUnits += opp;
      if (my > opp) {
        setsWonByMe++;
      } else {
        setsWonByOpponent++;
      }
    }

    if (setsWonByMe == setsWonByOpponent) {
      _showAlert('Invalid result', 'The match needs an overall winner.');
      return;
    }

    final iWon = setsWonByMe > setsWonByOpponent;

    setState(() => _submitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.post(
        Uri.parse('$apiUrl/matches/report'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'leagueId': widget.leagueId,
          'opponentId': _opponentId,
          'partnerId': _partnerId,
          'opponentPartnerId': _opponentPartnerId,
          'myUnits': totalMyUnits,
          'opponentUnits': totalOpponentUnits,
          'iWon': iWon,
          'setScores': setScores,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode != 201) {
        _showAlert(
          'Something went wrong',
          data['error'] ?? 'Please try again.',
        );
        return;
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (err) {
      _showAlert('Network error', 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingFixtures) {
      return Scaffold(
        appBar: AppBar(title: const Text('Report Match')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Schedule exists but this player has no pending fixtures left.
    if (_scheduleExists && _myPendingFixtures.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Report Match')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              "You don't have any pending scheduled matches left to report.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      );
    }

    final isDoubles = widget.format == 'doubles';

    return Scaffold(
      appBar: AppBar(title: const Text('Report Match')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_scheduleExists) ...[
              Text(
                'Select your scheduled match',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              ..._myPendingFixtures.map((fixture) {
                final selected =
                    _selectedFixture != null &&
                    _selectedFixture!['id'] == fixture['id'];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _selectFixture(fixture),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary.withValues(alpha: 0.08)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : Colors.grey.shade300,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: selected
                                ? AppColors.primary
                                : Colors.grey.shade400,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'vs ${_fixtureOpponentLabel(fixture)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Tier ${fixture['tier_number']}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 24),
            ] else ...[
              // No schedule generated for this league — fall back to free opponent selection.
              if (isDoubles) ...[
                Text(
                  'Your Partner',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: _partnerId,
                  items: widget.members
                      .map<DropdownMenuItem<int>>(
                        (m) => DropdownMenuItem(
                          value: m['id'],
                          child: Text(m['username']),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _partnerId = v),
                ),
                const SizedBox(height: 20),
              ],
              Text('Opponent', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _opponentId,
                items: widget.members
                    .map<DropdownMenuItem<int>>(
                      (m) => DropdownMenuItem(
                        value: m['id'],
                        child: Text(m['username']),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _opponentId = v),
              ),
              if (isDoubles) ...[
                const SizedBox(height: 20),
                Text(
                  "Opponent's Partner",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: _opponentPartnerId,
                  items: widget.members
                      .map<DropdownMenuItem<int>>(
                        (m) => DropdownMenuItem(
                          value: m['id'],
                          child: Text(m['username']),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _opponentPartnerId = v),
                ),
              ],
              const SizedBox(height: 24),
            ],
            Text(
              '$_unitLabel Scores',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ..._sets.asMap().entries.map((entry) {
              final index = entry.key;
              final set = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: set.myScore,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: '$_unitLabel ${index + 1} — You',
                          isDense: true,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
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
                    if (_sets.length > 1)
                      IconButton(
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          color: Colors.red,
                        ),
                        onPressed: () => _removeSet(index),
                      ),
                  ],
                ),
              );
            }),
            TextButton.icon(
              onPressed: _addSet,
              icon: const Icon(Icons.add),
              label: Text('Add $_unitLabel'),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _submitting ? null : _handleSubmit,
              child: _submitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text('Submit Result'),
            ),
          ],
        ),
      ),
    );
  }
}
