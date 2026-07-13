// select_sports_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String apiUrl = 'http://localhost:3000/api';

const List<String> skillLevels = [
  'Beginner',
  'Intermediate',
  'Advanced',
  'Expert',
];

class SelectSportsScreen extends StatefulWidget {
  const SelectSportsScreen({super.key});

  @override
  State<SelectSportsScreen> createState() => _SelectSportsScreenState();
}

class _SelectSportsScreenState extends State<SelectSportsScreen> {
  final List<String> _availableSports = ['Badminton', 'Tennis', 'Table Tennis'];

  final Set<String> _selectedSports = {};
  final Map<String, String> _skillLevels = {};
  bool _loading = false;

  void _toggleSport(String sport) {
    setState(() {
      if (_selectedSports.contains(sport)) {
        _selectedSports.remove(sport);
        _skillLevels.remove(sport);
      } else {
        _selectedSports.add(sport);
        _skillLevels[sport] = 'Intermediate';
      }
    });
  }

  Future<void> _handleContinue() async {
    if (_selectedSports.isEmpty) {
      _showAlert('Pick at least one', 'Select at least one sport to continue.');
      return;
    }

    setState(() => _loading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      if (token == null) {
        _showAlert('Session expired', 'Please log in again.');
        return;
      }

      final sportsPayload = _selectedSports.map((sport) {
        return {
          'sport': sport.toLowerCase().replaceAll(' ', '_'),
          'level': _skillLevels[sport]!.toLowerCase(),
        };
      }).toList();

      final response = await http.post(
        Uri.parse('$apiUrl/sports/select'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'sports': sportsPayload}),
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
      Navigator.pushReplacementNamed(context, '/home');
    } catch (err) {
      _showAlert(
        'Network error',
        'Could not reach the server. Check your connection.',
      );
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
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Text(
                'Which sports do you play?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pick your honest skill level so you get matched fairly from the start.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.builder(
                  itemCount: _availableSports.length,
                  itemBuilder: (context, index) {
                    final sport = _availableSports[index];
                    final isSelected = _selectedSports.contains(sport);
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      color: isSelected ? Colors.blue.shade50 : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isSelected
                              ? Colors.blue
                              : Colors.grey.shade300,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          CheckboxListTile(
                            title: Text(
                              sport,
                              style: const TextStyle(fontSize: 16),
                            ),
                            value: isSelected,
                            onChanged: (_) => _toggleSport(sport),
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                          if (isSelected)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: DropdownButtonFormField<String>(
                                initialValue: _skillLevels[sport],
                                decoration: const InputDecoration(
                                  labelText: 'Skill level',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: skillLevels
                                    .map(
                                      (level) => DropdownMenuItem(
                                        value: level,
                                        child: Text(level),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  setState(() => _skillLevels[sport] = value!);
                                },
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loading ? null : _handleContinue,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Continue', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
