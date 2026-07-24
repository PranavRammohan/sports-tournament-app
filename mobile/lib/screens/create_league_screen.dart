// create_league_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final TextEditingController _academyNameController = TextEditingController();
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

  bool _restrictByRating = false;
  final TextEditingController _minRatingController = TextEditingController();
  final TextEditingController _maxRatingController = TextEditingController();

  // Optional registration window — when null, joining has no date
  // restriction at all (matches current behavior).
  bool _restrictRegistration = false;
  DateTime? _registrationStart;
  DateTime? _registrationEnd;

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

  Future<void> _pickRegistrationDateTime({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart
        ? (_registrationStart ?? now)
        : (_registrationEnd ?? now);
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    setState(() {
      final combined = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (isStart) {
        _registrationStart = combined;
      } else {
        _registrationEnd = combined;
      }
    });
  }

  String _formatDateTimeDisplay(DateTime? dt) {
    if (dt == null) return 'Not set';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $hour12:$minute $ampm';
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

    double? minRating;
    double? maxRating;
    if (_restrictByRating) {
      minRating = double.tryParse(_minRatingController.text.trim());
      maxRating = double.tryParse(_maxRatingController.text.trim());
      if (minRating == null && maxRating == null) {
        _showAlert(
          'Missing info',
          'Enter at least a minimum or maximum rating, or turn off the rating restriction.',
        );
        return;
      }
      if (minRating != null && maxRating != null && minRating > maxRating) {
        _showAlert(
          'Invalid range',
          'Minimum rating cannot be higher than maximum rating.',
        );
        return;
      }
    }

    if (_restrictRegistration) {
      if (_registrationStart == null && _registrationEnd == null) {
        _showAlert(
          'Missing info',
          'Enter at least a registration start or end, or turn off the registration window.',
        );
        return;
      }
      if (_registrationStart != null &&
          _registrationEnd != null &&
          _registrationStart!.isAfter(_registrationEnd!)) {
        _showAlert(
          'Invalid window',
          'Registration start must be before registration end.',
        );
        return;
      }
    }

    HapticFeedback.lightImpact();
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
          'academyName': _academyNameController.text.trim().isEmpty
              ? null
              : _academyNameController.text.trim(),
          'minRating': minRating,
          'maxRating': maxRating,
          'registrationStart': _restrictRegistration
              ? _registrationStart?.toIso8601String()
              : null,
          'registrationEnd': _restrictRegistration
              ? _registrationEnd?.toIso8601String()
              : null,
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
            title: const Text('Tournament created!'),
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

  String? _ratingHintFor(String? sport) {
    switch (sport) {
      case 'Badminton':
        return 'e.g. 6000–8500';
      case 'Tennis':
        return 'e.g. 2.5–13';
      case 'Table Tennis':
        return 'e.g. 1000–2500';
      case 'Pickleball':
        return 'e.g. 2.5–7';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSingles = _selectedFormat == 'Singles';
    final ratingHint = _ratingHintFor(_selectedSport);

    return Scaffold(
      appBar: AppBar(title: const Text('Create Tournament')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Tournament Name',
                hintText: 'e.g. Koramangala Summer Tennis League',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _academyNameController,
              decoration: const InputDecoration(
                labelText: 'Academy Name (optional)',
                hintText: 'e.g. Ace Tennis Academy',
                prefixIcon: Icon(Icons.school_outlined),
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
              onChanged: (v) {
                HapticFeedback.selectionClick();
                setState(() => _hostEntersScores = v);
              },
              title: const Text('I will enter all match scores myself'),
              subtitle: const Text(
                'For academies or organizers running the event — scores you enter are confirmed instantly, no player confirmation needed. Otherwise, players need to report and confirm their match scores amongst themselves.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: !_hostPlays,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                setState(() => _hostPlays = !v);
              },
              title: const Text("I'm just organizing, not playing"),
              subtitle: const Text(
                "You won't appear on the leaderboard or schedule as a player.",
                style: TextStyle(fontSize: 12),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isPrivate,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                setState(() => _isPrivate = v);
              },
              title: const Text('Make this tournament private'),
              subtitle: const Text(
                "Won't show up in Browse Tournaments. Only people with the join code can join.",
                style: TextStyle(fontSize: 12),
              ),
            ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              'Who Can Join',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            RadioListTile<bool>(
              contentPadding: EdgeInsets.zero,
              value: false,
              groupValue: _restrictByRating,
              title: const Text('Open for all skill levels'),
              onChanged: (v) => setState(() => _restrictByRating = v!),
            ),
            RadioListTile<bool>(
              contentPadding: EdgeInsets.zero,
              value: true,
              groupValue: _restrictByRating,
              title: const Text('Only players within a rating range'),
              subtitle: _selectedSport == null
                  ? const Text(
                      'Select a sport above to see its rating scale',
                      style: TextStyle(fontSize: 11),
                    )
                  : null,
              onChanged: (v) => setState(() => _restrictByRating = v!),
            ),
            if (_restrictByRating) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minRatingController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Min rating',
                        hintText: ratingHint,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _maxRatingController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Max rating',
                        hintText: ratingHint,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Leave one blank for an open-ended range (e.g. only a minimum, no upper limit).',
                style: TextStyle(fontSize: 11),
              ),
            ],

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              'Registration Window',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Optional — restrict when players can join, e.g. only in the days leading up to the season. Leave off to allow joining any time.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _restrictRegistration,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                setState(() => _restrictRegistration = v);
              },
              title: const Text('Set a registration window'),
            ),
            if (_restrictRegistration) ...[
              const SizedBox(height: 6),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Registration opens',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: Text(_formatDateTimeDisplay(_registrationStart)),
                trailing: const Icon(Icons.event_outlined),
                onTap: () => _pickRegistrationDateTime(isStart: true),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Registration closes',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: Text(_formatDateTimeDisplay(_registrationEnd)),
                trailing: const Icon(Icons.event_outlined),
                onTap: () => _pickRegistrationDateTime(isStart: false),
              ),
              const SizedBox(height: 4),
              const Text(
                'Leave one blank for an open-ended window (e.g. only a closing date, open to join right away).',
                style: TextStyle(fontSize: 11),
              ),
            ],

            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _handleCreate,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create Tournament'),
            ),
          ],
        ),
      ),
    );
  }
}
