// add_sport_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../config.dart';

const Map<String, Map<String, num>> sportLevels = {
  'Badminton': {
    'beginner': 6000,
    'intermediate': 6500,
    'higher intermediate': 7000,
    'advanced': 7500,
    'pro': 8500,
  },
  'Tennis': {
    'beginner': 2.5,
    'lower intermediate': 4.5,
    'intermediate': 6.5,
    'intermediate advanced': 8.5,
    'advanced': 10.5,
    'pro': 13,
  },
  'Table Tennis': {
    'beginner': 1000,
    'early intermediate': 1400,
    'intermediate': 1600,
    'higher intermediate': 1800,
    'advanced': 2200,
    'pro': 2500,
  },
  'Pickleball': {
    'beginner': 2.5,
    'intermediate': 3.5,
    'mid-intermediate': 4,
    'advanced': 5,
    'pro': 7,
  },
};

String _capitalizeLevel(String level) {
  return level
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

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
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedSports.contains(sport)) {
        _selectedSports.remove(sport);
        _skillLevels.remove(sport);
      } else {
        _selectedSports.add(sport);
        _skillLevels[sport] = 'intermediate';
      }
    });
  }

  String _levelLabel(String sport, String level) {
    final rating = sportLevels[sport]?[level];
    return '${_capitalizeLevel(level)} (starts at $rating)';
  }

  Future<void> _handleSave() async {
    if (_selectedSports.isEmpty) {
      _showAlert('Pick at least one', 'Select at least one sport to add.');
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _loading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final sportsPayload = _selectedSports.map((sport) {
        return {
          'sport': sport.toLowerCase().replaceAll(' ', '_'),
          'level': _skillLevels[sport]!,
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
    final cardColor = Theme.of(context).cardColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unselectedBorder = isDark
        ? Colors.grey.shade700
        : Colors.grey.shade200;
    final titleColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark;

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
                      final levels = sportLevels[sport]!.keys.toList();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : unselectedBorder,
                            width: isSelected ? 1.5 : 1,
                          ),
                          boxShadow: AppShadows.card(isDark),
                        ),
                        child: Column(
                          children: [
                            CheckboxListTile(
                              title: Text(
                                sport,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: titleColor,
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
                                  items: levels
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
