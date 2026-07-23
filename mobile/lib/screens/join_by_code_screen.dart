// join_by_code_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../config.dart';
import 'league_detail_screen.dart';

class JoinByCodeScreen extends StatefulWidget {
  const JoinByCodeScreen({super.key});

  @override
  State<JoinByCodeScreen> createState() => _JoinByCodeScreenState();
}

class _JoinByCodeScreenState extends State<JoinByCodeScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _loading = false;

  Future<void> _handleJoin() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      _showAlert('Missing code', 'Please enter a join code.');
      return;
    }

    setState(() => _loading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.post(
        Uri.parse('$baseApiUrl/leagues/join-by-code'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'code': code}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode != 201) {
        _showAlert('Could not join', data['error'] ?? 'Please try again.');
        return;
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LeagueDetailScreen(leagueId: data['leagueId']),
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join with Code')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter the join code shared by the tournament host.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Join Code',
                prefixIcon: Icon(Icons.key_outlined),
              ),
              style: const TextStyle(fontSize: 18, letterSpacing: 3),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _handleJoin,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text('Join Tournament'),
            ),
          ],
        ),
      ),
    );
  }
}
