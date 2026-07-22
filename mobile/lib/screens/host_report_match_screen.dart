// host_report_match_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../config.dart';

class HostReportMatchScreen extends StatefulWidget {
  final int leagueId;
  final String sport;
  final List<dynamic> pendingFixtures; // schedule entries not yet completed

  const HostReportMatchScreen({
    super.key,
    required this.leagueId,
    required this.sport,
    required this.pendingFixtures,
  });

  @override
  State<HostReportMatchScreen> createState() => _HostReportMatchScreenState();
}

class _SetScore {
  final TextEditingController player1Score = TextEditingController();
  final TextEditingController player2Score = TextEditingController();
}

class _HostReportMatchScreenState extends State<HostReportMatchScreen> {
  Map<String, dynamic>? _selectedFixture;
  final List<_SetScore> _sets = [_SetScore()];
  bool _submitting = false;

  String get _unitLabel => widget.sport == 'tennis' ? 'Set' : 'Game';

  void _addSet() => setState(() => _sets.add(_SetScore()));
  void _removeSet(int index) {
    if (_sets.length > 1) setState(() => _sets.removeAt(index));
  }

  Future<void> _handleSubmit() async {
    if (_selectedFixture == null) {
      _showAlert('Missing info', 'Please select a match.');
      return;
    }

    int totalP1 = 0;
    int totalP2 = 0;
    int setsWonByP1 = 0;
    int setsWonByP2 = 0;
    final List<Map<String, int>> setScores = [];

    for (final s in _sets) {
      final p1 = int.tryParse(s.player1Score.text.trim());
      final p2 = int.tryParse(s.player2Score.text.trim());
      if (p1 == null || p2 == null) {
        _showAlert('Missing scores', 'Please fill in every $_unitLabel score.');
        return;
      }
      if (p1 == p2) {
        _showAlert('Invalid score', 'A $_unitLabel cannot end in a tie.');
        return;
      }
      // Stored from player1's perspective as "me"/"opponent" to match existing format
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
      _showAlert('Invalid result', 'The match needs an overall winner.');
      return;
    }

    setState(() => _submitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.post(
        Uri.parse('$baseApiUrl/matches/report-as-host'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'leagueId': widget.leagueId,
          'player1Id': _selectedFixture!['player1_id'],
          'player1PartnerId': _selectedFixture!['player1_partner_id'],
          'player2Id': _selectedFixture!['player2_id'],
          'player2PartnerId': _selectedFixture!['player2_partner_id'],
          'player1Units': totalP1,
          'player2Units': totalP2,
          'player1Won': setsWonByP1 > setsWonByP2,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  String _fixtureLabel(Map<String, dynamic> fixture) {
    final isDoubles = fixture['player1_partner_username'] != null;
    final team1 = isDoubles
        ? '${fixture['player1_username']} & ${fixture['player1_partner_username']}'
        : fixture['player1_username'];
    final team2 = isDoubles
        ? '${fixture['player2_username']} & ${fixture['player2_partner_username']}'
        : fixture['player2_username'];
    return '$team1 vs $team2';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pendingFixtures.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Enter Match Score')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No pending scheduled matches to enter.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final unselectedBorder = isDark
        ? Colors.grey.shade600
        : Colors.grey.shade300;
    final unselectedIconColor = isDark
        ? Colors.grey.shade500
        : Colors.grey.shade400;
    final titleColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark;

    return Scaffold(
      appBar: AppBar(title: const Text('Enter Match Score')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Select match',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            ...widget.pendingFixtures.map((fixture) {
              final selected =
                  _selectedFixture != null &&
                  _selectedFixture!['id'] == fixture['id'];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _selectedFixture = fixture),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary.withValues(
                              alpha: isDark ? 0.18 : 0.06,
                            )
                          : cardColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? AppColors.primary : unselectedBorder,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selected ? Icons.check_circle : Icons.circle_outlined,
                          color: selected
                              ? AppColors.primary
                              : unselectedIconColor,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _fixtureLabel(fixture),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: titleColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
            if (_selectedFixture != null) ...[
              Text(
                '$_unitLabel Scores',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ..._sets.asMap().entries.map((entry) {
                final index = entry.key;
                final set = entry.value;
                final isDoubles =
                    _selectedFixture!['player1_partner_username'] != null;
                final p1Label = isDoubles
                    ? '${_selectedFixture!['player1_username']} & partner'
                    : _selectedFixture!['player1_username'];
                final p2Label = isDoubles
                    ? '${_selectedFixture!['player2_username']} & partner'
                    : _selectedFixture!['player2_username'];

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: set.player1Score,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: '$_unitLabel ${index + 1} — $p1Label',
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
                          controller: set.player2Score,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: p2Label,
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
                    : const Text('Submit Score'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
