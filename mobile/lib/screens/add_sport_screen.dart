// add_sport_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../config.dart';

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
const List<String> allSports = [
  'Badminton',
  'Tennis',
  'Table Tennis',
  'Pickleball',
];

class AddSportScreen extends StatefulWidget {
  final List<String> existingSports;

  const AddSportScreen({super.key, required this.existingSports});

  @override
  State<AddSportScreen> createState() => _AddSportScreenState();
}

class _AddSportScreenState extends State<AddSportScreen> {
  final Set<String> _selectedSports = {};
  final Map<String, String> _skillLevels = {};
  bool _loading = false;

  List<String> get _availableSports {
    return allSports.where((sport) {
      final key = sport.toLowerCase().replaceAll(' ', '_');
      return !widget.existingSports.contains(key);
    }).toList();
  }

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

  Future<void> _handleSave() async {
    if (_selectedSports.isEmpty) {
      _showAlert('Pick at least one', 'Select at least one sport to add.');
      return;
    }

    setState(() => _loading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final sportsPayload = _selectedSports.map((sport) {
        return {
          'sport': sport.toLowerCase().replaceAll(' ', '_'),
          'level': _skillLevels[sport]!.toLowerCase(),
        };
      }).toList();

      final response = await http.post(
        Uri.parse('$baseApiUrl/sports/select'),
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
    final available = _availableSports;

    return Scaffold(
      appBar: AppBar(title: const Text('Add a Sport')),
      body: available.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  "You've already added every sport we support.",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: available.map((sport) {
                      final isSelected = _selectedSports.contains(sport);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : Colors.grey.shade200,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            CheckboxListTile(
                              title: Text(
                                sport,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              value: isSelected,
                              onChanged: (_) => _toggleSport(sport),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                            if (isSelected)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  12,
                                ),
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
                                          child: Text(
                                            _levelLabel(sport, level),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) => setState(
                                    () => _skillLevels[sport] = value!,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton(
                    onPressed: _loading ? null : _handleSave,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
    );
  }
}
