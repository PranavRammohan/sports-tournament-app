// add_manual_match_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class AddManualMatchScreen extends StatefulWidget {
  final int leagueId;
  final String format;
  final List<dynamic> members;

  const AddManualMatchScreen({
    super.key,
    required this.leagueId,
    required this.format,
    required this.members,
  });

  @override
  State<AddManualMatchScreen> createState() => _AddManualMatchScreenState();
}

class _AddManualMatchScreenState extends State<AddManualMatchScreen> {
  int? _player1Id;
  int? _player1PartnerId;
  int? _player2Id;
  int? _player2PartnerId;
  bool _submitting = false;

  Future<void> _handleAdd() async {
    final isDoubles = widget.format == 'doubles';

    if (_player1Id == null || _player2Id == null) {
      _showAlert('Missing info', 'Please select both sides of the match.');
      return;
    }
    if (isDoubles && (_player1PartnerId == null || _player2PartnerId == null)) {
      _showAlert(
        'Missing info',
        'Doubles matches need both partners selected.',
      );
      return;
    }
    final allSelected = [
      _player1Id,
      _player2Id,
      _player1PartnerId,
      _player2PartnerId,
    ].whereType<int>().toList();
    if (allSelected.toSet().length != allSelected.length) {
      _showAlert(
        'Duplicate selection',
        'The same player cannot appear twice in one match.',
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.post(
        Uri.parse('$baseApiUrl/leagues/${widget.leagueId}/add-manual-match'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'player1Id': _player1Id,
          'player1PartnerId': _player1PartnerId,
          'player2Id': _player2Id,
          'player2PartnerId': _player2PartnerId,
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

  List<DropdownMenuItem<int>> _memberItems() {
    return widget.members
        .map<DropdownMenuItem<int>>(
          (m) => DropdownMenuItem(value: m['id'], child: Text(m['username'])),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDoubles = widget.format == 'doubles';

    return Scaffold(
      appBar: AppBar(title: const Text('Add Match')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Side 1', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _player1Id,
              decoration: const InputDecoration(labelText: 'Player'),
              items: _memberItems(),
              onChanged: (v) => setState(() => _player1Id = v),
            ),
            if (isDoubles) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _player1PartnerId,
                decoration: const InputDecoration(labelText: 'Partner'),
                items: _memberItems(),
                onChanged: (v) => setState(() => _player1PartnerId = v),
              ),
            ],
            const SizedBox(height: 24),
            Text('Side 2', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _player2Id,
              decoration: const InputDecoration(labelText: 'Player'),
              items: _memberItems(),
              onChanged: (v) => setState(() => _player2Id = v),
            ),
            if (isDoubles) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _player2PartnerId,
                decoration: const InputDecoration(labelText: 'Partner'),
                items: _memberItems(),
                onChanged: (v) => setState(() => _player2PartnerId = v),
              ),
            ],
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _submitting ? null : _handleAdd,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text('Add Match'),
            ),
          ],
        ),
      ),
    );
  }
}
