// select_sports_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

const String apiUrl = 'http://localhost:3000/api';

const Map<String, Map<String, num>> startingRatings = {
  'Badminton': {
    'Beginner': 1500,
    'Intermediate': 3000,
    'Advanced': 5000,
    'Expert': 7000,
  },
  'Tennis': {
    'Beginner': 2.5,
    'Intermediate': 5.0,
    'Advanced': 8.5,
    'Expert': 12.0,
  },
  'Table Tennis': {
    'Beginner': 800,
    'Intermediate': 1200,
    'Advanced': 1600,
    'Expert': 2000,
  },
  'Pickleball': {
    'Beginner': 2.5,
    'Intermediate': 3.5,
    'Advanced': 5.0,
    'Expert': 6.5,
  },
};

const List<String> skillLevels = [
  'Beginner',
  'Intermediate',
  'Advanced',
  'Expert',
];

// Emoji reads more accurately than Flutter's built-in icon set for these sports.
const Map<String, String> sportEmojis = {
  'Badminton': '🏸',
  'Tennis': '🎾',
  'Table Tennis': '🏓',
  'Pickleball':
      '🥒', // closest widely-supported paddle-sport glyph; swap later if a better one appears
};

class SelectSportsScreen extends StatefulWidget {
  const SelectSportsScreen({super.key});

  @override
  State<SelectSportsScreen> createState() => _SelectSportsScreenState();
}

class _SelectSportsScreenState extends State<SelectSportsScreen> {
  final List<String> _availableSports = [
    'Badminton',
    'Tennis',
    'Table Tennis',
    'Pickleball',
  ];

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

  String _levelLabel(String sport, String level) {
    final rating = startingRatings[sport]?[level];
    return '$level (starts at $rating)';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Choose Your Sports')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                'Pick your honest skill level so you get matched fairly from the start.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                itemCount: _availableSports.length,
                itemBuilder: (context, index) {
                  final sport = _availableSports[index];
                  final isSelected = _selectedSports.contains(sport);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : Colors.grey.shade200,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _toggleSport(sport),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primary.withValues(
                                            alpha: 0.12,
                                          )
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Text(
                                      sportEmojis[sport] ?? '🏅',
                                      style: const TextStyle(fontSize: 22),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    sport,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                                Icon(
                                  isSelected
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  color: isSelected
                                      ? AppColors.primary
                                      : Colors.grey.shade400,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (isSelected)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                            child: DropdownButtonFormField<String>(
                              initialValue: _skillLevels[sport],
                              decoration: const InputDecoration(
                                labelText: 'Skill level',
                                isDense: true,
                              ),
                              items: skillLevels
                                  .map(
                                    (level) => DropdownMenuItem(
                                      value: level,
                                      child: Text(_levelLabel(sport, level)),
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
            Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton(
                onPressed: _loading ? null : _handleContinue,
                child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
