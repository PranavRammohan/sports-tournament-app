// create_league_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

const List<String> sportsList = [
  'Badminton',
  'Tennis',
  'Table Tennis',
  'Pickleball',
];

const List<String> bangaloreAreas = [
  'Koramangala',
  'Indiranagar',
  'HSR Layout',
  'BTM Layout',
  'Jayanagar',
  'JP Nagar',
  'Whitefield',
  'Marathahalli',
  'Electronic City',
  'Bellandur',
  'Sarjapur Road',
  'Hebbal',
  'Yelahanka',
  'Malleshwaram',
  'Rajajinagar',
  'Basavanagudi',
  'Banashankari',
  'RT Nagar',
  'Frazer Town',
  'Ulsoor',
  'MG Road',
  'Domlur',
  'CV Raman Nagar',
  'Kalyan Nagar',
  'Banaswadi',
  'Vijayanagar',
  'Rajarajeshwari Nagar',
  'Kengeri',
  'Yeshwanthpur',
  'Nagarbhavi',
  'Hennur',
  'Bannerghatta Road',
  'KR Puram',
  'Mahadevapura',
  'Uttarahalli',
  'Kanakapura Road',
  'Konanakunte',
  'Anjanapura',
  'Padmanabhanagar',
  'Girinagar',
  'Kumaraswamy Layout',
  'Vasanthapura',
  'Chikkalasandra',
  'Hulimavu',
  'Bommanahalli',
  'Begur',
  'Arekere',
  'Gottigere',
  'Silk Board',
  'Madiwala',
  'Bilekahalli',
  'Kudlu',
];

class CreateLeagueScreen extends StatefulWidget {
  const CreateLeagueScreen({super.key});

  @override
  State<CreateLeagueScreen> createState() => _CreateLeagueScreenState();
}

class _CreateLeagueScreenState extends State<CreateLeagueScreen> {
  final TextEditingController _nameController = TextEditingController();
  String? _selectedSport;
  String? _selectedArea;
  String? _selectedFormat;
  String? _selectedGenderCategory;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _loading = false;

  String _scheduleType = 'round_robin';
  final TextEditingController _matchesPerPlayerController =
      TextEditingController();
  bool _hostEntersScores = false;
  bool _hostPlays = true;
  bool _isPrivate = false;

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _handleCreate() async {
    final name = _nameController.text.trim();

    if (name.isEmpty ||
        _selectedSport == null ||
        _selectedArea == null ||
        _selectedFormat == null ||
        _selectedGenderCategory == null ||
        _startDate == null ||
        _endDate == null) {
      _showAlert('Missing info', 'Please fill in all fields.');
      return;
    }
    if (_endDate!.isBefore(_startDate!)) {
      _showAlert('Invalid dates', 'End date must be after start date.');
      return;
    }

    int? matchesPerPlayer;
    if (_scheduleType == 'matches_per_player') {
      matchesPerPlayer = int.tryParse(_matchesPerPlayerController.text.trim());
      if (matchesPerPlayer == null || matchesPerPlayer < 1) {
        _showAlert(
          'Missing info',
          'Please enter how many matches each player should play.',
        );
        return;
      }
    }

    setState(() => _loading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.post(
        Uri.parse('$baseApiUrl/leagues/create'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'name': name,
          'sport': _selectedSport!.toLowerCase().replaceAll(' ', '_'),
          'area': _selectedArea,
          'seasonStart': _startDate!.toIso8601String().split('T')[0],
          'seasonEnd': _endDate!.toIso8601String().split('T')[0],
          'format': _selectedFormat!.toLowerCase(),
          'genderCategory': _selectedGenderCategory == "Men's"
              ? 'mens'
              : 'womens',
          'scheduleType': _scheduleType,
          'matchesPerPlayer': matchesPerPlayer,
          'hostEntersScores': _hostEntersScores,
          'hostPlays': _hostPlays,
          'isPrivate': _isPrivate,
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

      final league = data['league'];
      if (_isPrivate && league['join_code'] != null) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            title: const Text('League created!'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Share this code with the people you want to invite:',
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    league['join_code'],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
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

  String _formatDate(DateTime? d) =>
      d == null ? 'Select date' : '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final isSingles = _selectedFormat == 'Singles';

    return Scaffold(
      appBar: AppBar(title: const Text('Create League')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'League Name',
                hintText: 'e.g. Koramangala Summer Tennis League',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedSport,
              decoration: const InputDecoration(labelText: 'Sport'),
              items: sportsList
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedSport = v),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedFormat,
              decoration: const InputDecoration(labelText: 'Format'),
              items: const [
                DropdownMenuItem(value: 'Singles', child: Text('Singles')),
                DropdownMenuItem(value: 'Doubles', child: Text('Doubles')),
              ],
              onChanged: (v) {
                setState(() {
                  _selectedFormat = v;
                  // Knockout is singles-only; fall back if doubles is chosen.
                  if (v == 'Doubles' && _scheduleType == 'knockout') {
                    _scheduleType = 'round_robin';
                  }
                });
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedGenderCategory,
              decoration: const InputDecoration(labelText: 'Category'),
              items: const [
                DropdownMenuItem(value: "Men's", child: Text("Men's")),
                DropdownMenuItem(value: "Women's", child: Text("Women's")),
              ],
              onChanged: (v) => setState(() => _selectedGenderCategory = v),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedArea,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Area'),
              items: bangaloreAreas
                  .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedArea = v),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Season start: ${_formatDate(_startDate)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _pickDate(isStart: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Season end: ${_formatDate(_endDate)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _pickDate(isStart: false),
            ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              'Match Format',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),

            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: 'round_robin',
              groupValue: _scheduleType,
              title: const Text('Round Robin (everyone plays everyone)'),
              subtitle: const Text(
                'Best for 7 or fewer players',
                style: TextStyle(fontSize: 11),
              ),
              onChanged: (v) => setState(() => _scheduleType = v!),
            ),
            if (isSingles)
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: 'matches_per_player',
                groupValue: _scheduleType,
                title: const Text('Fixed number of matches per player'),
                subtitle: const Text(
                  'Good for larger groups',
                  style: TextStyle(fontSize: 11),
                ),
                onChanged: (v) => setState(() => _scheduleType = v!),
              ),
            if (isSingles && _scheduleType == 'matches_per_player')
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: TextField(
                  controller: _matchesPerPlayerController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Matches per player',
                    isDense: true,
                    hintText: 'e.g. 5',
                  ),
                ),
              ),
            if (isSingles)
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: 'knockout',
                groupValue: _scheduleType,
                title: const Text('Knockout (seeded, single elimination)'),
                subtitle: const Text(
                  'Needs an exact power-of-2 player count (2, 4, 8, 16...)',
                  style: TextStyle(fontSize: 11),
                ),
                onChanged: (v) => setState(() => _scheduleType = v!),
              ),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: 'custom',
              groupValue: _scheduleType,
              title: const Text('Custom — I\'ll decide who plays who'),
              subtitle: const Text(
                'Add matches manually, any time',
                style: TextStyle(fontSize: 11),
              ),
              onChanged: (v) => setState(() => _scheduleType = v!),
            ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _hostEntersScores,
              onChanged: (v) => setState(() => _hostEntersScores = v),
              title: const Text('I will enter all match scores myself'),
              subtitle: const Text(
                'For academies or organizers running the event — scores you enter are confirmed instantly, no player confirmation needed.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: !_hostPlays,
              onChanged: (v) => setState(() => _hostPlays = !v),
              title: const Text("I'm just organizing, not playing"),
              subtitle: const Text(
                "You won't appear on the leaderboard or schedule as a player.",
                style: TextStyle(fontSize: 12),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isPrivate,
              onChanged: (v) => setState(() => _isPrivate = v),
              title: const Text('Make this league private'),
              subtitle: const Text(
                "Won't show up in Browse Leagues. Only people with the join code can join.",
                style: TextStyle(fontSize: 12),
              ),
            ),

            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _handleCreate,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create League'),
            ),
          ],
        ),
      ),
    );
  }
}
