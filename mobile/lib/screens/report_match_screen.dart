// report_match_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String apiUrl = 'http://localhost:3000/api';

class ReportMatchScreen extends StatefulWidget {
  final int leagueId;
  final String format; // 'singles' or 'doubles'
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
  int? _opponentId;
  int? _partnerId;
  int? _opponentPartnerId;
  final List<_SetScore> _sets = [_SetScore()];
  bool _loading = false;

  String get _unitLabel => widget.sport == 'tennis' ? 'Set' : 'Game';

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

    setState(() => _loading = true);

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
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
    final isDoubles = widget.format == 'doubles';

    return Scaffold(
      appBar: AppBar(title: const Text('Report Match')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isDoubles) ...[
              const Text(
                'Your Partner',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _partnerId,
                decoration: const InputDecoration(border: OutlineInputBorder()),
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
            const Text(
              'Opponent',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _opponentId,
              decoration: const InputDecoration(border: OutlineInputBorder()),
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
              const Text(
                "Opponent's Partner",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _opponentPartnerId,
                decoration: const InputDecoration(border: OutlineInputBorder()),
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
            Text(
              '$_unitLabel Scores',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
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
                          border: const OutlineInputBorder(),
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
                        decoration: InputDecoration(
                          labelText: 'Opponent',
                          border: const OutlineInputBorder(),
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
              onPressed: _loading ? null : _handleSubmit,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit Result'),
            ),
          ],
        ),
      ),
    );
  }
}
