// edit_league_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../config.dart';
import 'signup_screen.dart' show bangaloreAreas;
import 'regenerate_schedule_dialog.dart';

class EditLeagueScreen extends StatefulWidget {
  final Map<String, dynamic> league;
  final bool hasConfirmedMatches;

  const EditLeagueScreen({
    super.key,
    required this.league,
    required this.hasConfirmedMatches,
  });

  @override
  State<EditLeagueScreen> createState() => _EditLeagueScreenState();
}

class _EditLeagueScreenState extends State<EditLeagueScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _academyController = TextEditingController();
  String? _selectedArea;
  DateTime? _seasonStart;
  DateTime? _seasonEnd;
  bool _isPrivate = false;
  bool _hostEntersScores = false;
  bool _saving = false;
  bool _changingFormat = false;
  String? _joinCode;

  late String _scheduleType;
  int? _matchesPerPlayer;

  bool _restrictRegistration = false;
  DateTime? _registrationStart;
  DateTime? _registrationEnd;

  @override
  void initState() {
    super.initState();
    final l = widget.league;
    _nameController.text = l['name'] ?? '';
    _academyController.text = l['academy_name'] ?? '';
    _selectedArea = l['area'];
    _seasonStart = DateTime.tryParse(l['season_start']?.toString() ?? '');
    _seasonEnd = DateTime.tryParse(l['season_end']?.toString() ?? '');
    _isPrivate = l['is_private'] == true;
    _hostEntersScores = l['host_enters_scores'] == true;
    _joinCode = l['join_code'];
    _scheduleType = l['schedule_type'] ?? 'round_robin';
    _matchesPerPlayer = l['matches_per_player'];

    _registrationStart = l['registration_start'] != null
        ? DateTime.tryParse(l['registration_start'].toString())?.toLocal()
        : null;
    _registrationEnd = l['registration_end'] != null
        ? DateTime.tryParse(l['registration_end'].toString())?.toLocal()
        : null;
    _restrictRegistration =
        _registrationStart != null || _registrationEnd != null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _academyController.dispose();
    super.dispose();
  }

  String _formatForApi(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _formatDisplayDate(DateTime? d) {
    if (d == null) return 'Select date';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
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

  String _scheduleTypeLabel(String type) {
    switch (type) {
      case 'round_robin':
        return 'Round Robin';
      case 'matches_per_player':
        return 'Fixed matches per player${_matchesPerPlayer != null ? ' ($_matchesPerPlayer each)' : ''}';
      case 'knockout':
        return 'Knockout';
      case 'custom':
        return 'Custom';
      default:
        return type;
    }
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart
        ? (_seasonStart ?? DateTime.now())
        : (_seasonEnd ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _seasonStart = picked;
      } else {
        _seasonEnd = picked;
      }
    });
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

  Future<void> _changeFormat() async {
    final result = await showDialog<RegenerateScheduleResult>(
      context: context,
      builder: (ctx) => RegenerateScheduleDialog(
        currentScheduleType: _scheduleType,
        currentMatchesPerPlayer: _matchesPerPlayer,
        isSingles: widget.league['format'] == 'singles',
      ),
    );
    if (result == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('Confirm format change?'),
        content: const Text(
          'This rebuilds the fixture list for everyone currently in the tournament. Confirmed results stay in history, but any pending unconfirmed reports and any existing bracket will be discarded. This takes effect immediately and closes this screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    HapticFeedback.mediumImpact();
    setState(() => _changingFormat = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.post(
        Uri.parse(
          '$baseApiUrl/leagues/${widget.league['id']}/regenerate-schedule',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'scheduleType': result.scheduleType,
          'matchesPerPlayer': result.matchesPerPlayer,
        }),
      );
      final data = jsonDecode(response.body);

      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 201) {
        Navigator.pop(context, true);
      } else {
        _showAlert(
          'Could not change format',
          data['error'] ?? 'Something went wrong.',
        );
      }
    } catch (err) {
      _showAlert('Network error', 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _changingFormat = false);
    }
  }

  Future<void> _handleSave() async {
    if (_nameController.text.trim().isEmpty) {
      _showAlert('Missing name', 'Please enter a tournament name.');
      return;
    }
    if (_selectedArea == null) {
      _showAlert('Missing area', 'Please select an area.');
      return;
    }
    if (_seasonStart == null || _seasonEnd == null) {
      _showAlert('Missing dates', 'Please select both season dates.');
      return;
    }
    if (_seasonEnd!.isBefore(_seasonStart!)) {
      _showAlert('Invalid dates', 'Season end must be after season start.');
      return;
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
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.put(
        Uri.parse('$baseApiUrl/leagues/${widget.league['id']}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'name': _nameController.text.trim(),
          'area': _selectedArea,
          'seasonStart': _formatForApi(_seasonStart!),
          'seasonEnd': _formatForApi(_seasonEnd!),
          'academyName': _academyController.text.trim(),
          'isPrivate': _isPrivate,
          if (!widget.hasConfirmedMatches)
            'hostEntersScores': _hostEntersScores,
          'registrationStart': _restrictRegistration
              ? _registrationStart?.toIso8601String()
              : null,
          'registrationEnd': _restrictRegistration
              ? _registrationEnd?.toIso8601String()
              : null,
        }),
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;
      if (response.statusCode == 200) {
        if (data['league']?['join_code'] != null) {
          setState(() => _joinCode = data['league']['join_code']);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tournament updated.'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      } else {
        _showAlert('Could not save', data['error'] ?? 'Something went wrong.');
      }
    } catch (err) {
      _showAlert('Network error', 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _saving = false);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Tournament')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Tournament Name',
                prefixIcon: Icon(Icons.emoji_events_outlined),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _selectedArea,
              decoration: const InputDecoration(
                labelText: 'Area',
                prefixIcon: Icon(Icons.map_outlined),
              ),
              isExpanded: true,
              items: bangaloreAreas
                  .map(
                    (area) => DropdownMenuItem(value: area, child: Text(area)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _selectedArea = value),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _academyController,
              decoration: const InputDecoration(
                labelText: 'Academy name (optional)',
                prefixIcon: Icon(Icons.school_outlined),
              ),
            ),
            const SizedBox(height: 20),
            Text('Season', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(true),
                    child: Text('Start: ${_formatDisplayDate(_seasonStart)}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(false),
                    child: Text('End: ${_formatDisplayDate(_seasonEnd)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Match Format',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade400),
                boxShadow: AppShadows.card(isDark),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _scheduleTypeLabel(_scheduleType),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: _changingFormat ? null : _changeFormat,
                    child: _changingFormat
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Change'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade400),
                boxShadow: AppShadows.card(isDark),
              ),
              child: SwitchListTile(
                value: _isPrivate,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  setState(() => _isPrivate = v);
                },
                title: const Text(
                  'Private Tournament',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: const Text(
                  'Only people with a join code can join',
                  style: TextStyle(fontSize: 12),
                ),
                secondary: const Icon(Icons.lock_outline),
              ),
            ),
            if (_isPrivate && _joinCode != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade400),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.key_outlined, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Join code: $_joinCode',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade400),
                boxShadow: AppShadows.card(isDark),
              ),
              child: SwitchListTile(
                value: _hostEntersScores,
                onChanged: widget.hasConfirmedMatches
                    ? null
                    : (v) {
                        HapticFeedback.selectionClick();
                        setState(() => _hostEntersScores = v);
                      },
                title: const Text(
                  'Host Enters Scores',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: Text(
                  widget.hasConfirmedMatches
                      ? 'Locked — matches have already been confirmed in this tournament'
                      : 'If on, only you can enter match results',
                  style: const TextStyle(fontSize: 12),
                ),
                secondary: const Icon(Icons.edit_note),
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Registration Window',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Optional — restrict when players can join. Leave off to allow joining any time.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade400),
                boxShadow: AppShadows.card(isDark),
              ),
              child: SwitchListTile(
                value: _restrictRegistration,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  setState(() => _restrictRegistration = v);
                },
                title: const Text(
                  'Set a registration window',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                secondary: const Icon(Icons.event_outlined),
              ),
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
                trailing: const Icon(Icons.chevron_right),
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
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pickRegistrationDateTime(isStart: false),
              ),
            ],
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _saving ? null : _handleSave,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}
