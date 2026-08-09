// edit_league_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../main.dart';
import '../config.dart';
import '../constants/areas.dart';
import '../validators.dart';
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
  final _formKey = GlobalKey<FormState>();
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

  bool get _isDoubles => widget.league['format'] == 'doubles';
  late String _initialPartnerMode;
  late String _partnerMode;
  bool _anyPartnershipsStarted = false;
  bool _loadingPartnerStatus = false;

  bool _restrictRegistration = false;
  DateTime? _registrationStart;
  DateTime? _registrationEnd;

  bool _pointsEnabled = true;
  final TextEditingController _pointsWinController = TextEditingController();
  final TextEditingController _pointsLossController = TextEditingController();

  bool _restrictCapacity = false;
  final TextEditingController _maxPlayersController = TextEditingController();

  bool _restrictByRating = false;
  final TextEditingController _minRatingController = TextEditingController();
  final TextEditingController _maxRatingController = TextEditingController();

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
    _initialPartnerMode = l['partner_mode'] ?? 'host_auto';
    _partnerMode = _initialPartnerMode;

    _registrationStart = l['registration_start'] != null
        ? DateTime.tryParse(l['registration_start'].toString())?.toLocal()
        : null;
    _registrationEnd = l['registration_end'] != null
        ? DateTime.tryParse(l['registration_end'].toString())?.toLocal()
        : null;
    _restrictRegistration =
        _registrationStart != null || _registrationEnd != null;

    _pointsEnabled = l['points_enabled'] != false;
    _pointsWinController.text = (l['points_win'] ?? 2).toString();
    _pointsLossController.text = (l['points_loss'] ?? 0).toString();

    _restrictCapacity = l['max_players'] != null;
    if (l['max_players'] != null) {
      _maxPlayersController.text = l['max_players'].toString();
    }

    _restrictByRating = l['min_rating'] != null || l['max_rating'] != null;
    if (l['min_rating'] != null) {
      _minRatingController.text = l['min_rating'].toString();
    }
    if (l['max_rating'] != null) {
      _maxRatingController.text = l['max_rating'].toString();
    }

    if (_isDoubles) {
      _loadPartnerStatus();
    }
  }

  // Fix I: proactively check whether any partnerships have already started
  // forming, so the partner-mode dropdown can be locked upfront instead of
  // only failing with an error after the host taps Save.
  Future<void> _loadPartnerStatus() async {
    setState(() => _loadingPartnerStatus = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final response = await http.get(
        Uri.parse('$baseApiUrl/leagues/${widget.league['id']}/partners'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final members = data['members'] as List;
        final anyStarted = members.any((m) => m['partner_status'] != null);
        if (mounted) setState(() => _anyPartnershipsStarted = anyStarted);
      }
    } catch (err) {
      // Non-critical — worst case the dropdown stays enabled and the host
      // finds out via the normal save-time error instead.
    } finally {
      if (mounted) setState(() => _loadingPartnerStatus = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _academyController.dispose();
    _pointsWinController.dispose();
    _pointsLossController.dispose();
    _maxPlayersController.dispose();
    _minRatingController.dispose();
    _maxRatingController.dispose();
    super.dispose();
  }

  String _formatForApi(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  // Same ranges as create_league_screen.dart's _ratingHintFor, keyed off
  // the lowercase sport values the backend actually stores (widget.league
  // never has the display-cased 'Badminton'/'Tennis'/... create's own
  // sport dropdown uses).
  String? _ratingHintFor(String? sport) {
    switch (sport) {
      case 'badminton':
        return 'e.g. 6000–8500';
      case 'tennis':
        return 'e.g. 2.5–13';
      case 'table_tennis':
        return 'e.g. 1000–2500';
      case 'pickleball':
        return 'e.g. 2.5–7';
      default:
        return null;
    }
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
        return _isDoubles
            ? 'Fixed matches per team${_matchesPerPlayer != null ? ' ($_matchesPerPlayer each)' : ''}'
            : 'Fixed matches per player${_matchesPerPlayer != null ? ' ($_matchesPerPlayer each)' : ''}';
      case 'knockout':
        return 'Knockout';
      case 'custom':
        return 'Custom';
      case 'groups':
        return 'Groups';
      default:
        return type;
    }
  }

  String _partnerModeLabel(String mode) {
    switch (mode) {
      case 'self_select':
        return 'Players choose their own partner';
      case 'host_manual':
        return 'I assign partners myself';
      case 'host_auto':
      default:
        return 'Automatic (balanced by rating)';
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

  Future<void> _changeFormat({
    RegenerateScheduleResult? retryResult,
    bool force = false,
  }) async {
    var result = retryResult;
    if (result == null) {
      result = await showDialog<RegenerateScheduleResult>(
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          title: const Text('Confirm format change?'),
          content: const Text(
            'This wipes ALL match history for this tournament — every confirmed result, rating change, and point awarded so far will be reversed — and rebuilds the fixture list from scratch. This cannot be undone, takes effect immediately, and closes this screen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Wipe & Continue',
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

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
          'force': force,
        }),
      );
      final data = jsonDecode(response.body);

      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 201) {
        Navigator.pop(context, true);
      } else if (data['estimatedMatches'] != null) {
        setState(() => _changingFormat = false);
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            title: const Text('That\'s a lot of matches'),
            content: Text('${data['error']} Continue anyway?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Generate Anyway'),
              ),
            ],
          ),
        );
        if (proceed == true) {
          await _changeFormat(retryResult: result, force: true);
        }
        return;
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
    if (!_formKey.currentState!.validate()) return;
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

    int? maxPlayers;
    if (_restrictCapacity) {
      maxPlayers = int.tryParse(_maxPlayersController.text.trim());
      final memberCount = widget.league['member_count'] ?? 0;
      if (maxPlayers == null || maxPlayers < 1) {
        _showAlert(
          'Missing info',
          'Enter a max player count of at least 1, or turn off the player limit.',
        );
        return;
      }
      if (maxPlayers < memberCount) {
        _showAlert(
          'Too low',
          "Max players can't be set below the current roster size ($memberCount).",
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

    int? pointsWin;
    int? pointsLoss;
    if (_pointsEnabled) {
      pointsWin = int.tryParse(_pointsWinController.text.trim());
      pointsLoss = int.tryParse(_pointsLossController.text.trim());
      if (pointsWin == null || pointsWin < 0 || pointsLoss == null || pointsLoss < 0) {
        _showAlert(
          'Missing info',
          'Please enter valid points for a win and a loss (0 or more).',
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
          if (_isDoubles && _partnerMode != _initialPartnerMode)
            'partnerMode': _partnerMode,
          'registrationStart': _restrictRegistration
              ? _registrationStart?.toIso8601String()
              : null,
          'registrationEnd': _restrictRegistration
              ? _registrationEnd?.toIso8601String()
              : null,
          'pointsEnabled': _pointsEnabled,
          'pointsWin': _pointsEnabled ? pointsWin : null,
          'pointsLoss': _pointsEnabled ? pointsLoss : null,
          'maxPlayers': _restrictCapacity ? maxPlayers : null,
          'minRating': _restrictByRating ? minRating : null,
          'maxRating': _restrictByRating ? maxRating : null,
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
    final ratingHint = _ratingHintFor(widget.league['sport']);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Tournament')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nameController,
              validator: (v) => requiredField(v, label: 'Tournament name'),
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
            const SizedBox(height: 4),
            Text(
              widget.league['format'] == 'doubles'
                  ? 'Doubles tournament. Sport, format, and category cannot be changed after creation — this affects players\' rating history.'
                  : 'Singles tournament. Sport, format, and category cannot be changed after creation — this affects players\' rating history.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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
            Text(
              'Tournament Points',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Award points for a win/loss so players can be ranked on a leaderboard. Changes only affect matches confirmed from now on. A group can override this from Manage Groups.',
              style: TextStyle(fontSize: 11),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _pointsEnabled,
              onChanged: (v) => setState(() => _pointsEnabled = v),
              title: const Text('Award tournament points'),
            ),
            if (_pointsEnabled)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pointsWinController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Points for a win',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _pointsLossController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Points for a loss',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 14),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _restrictCapacity,
              onChanged: (v) => setState(() => _restrictCapacity = v),
              title: const Text('Limit number of players'),
            ),
            if (_restrictCapacity)
              TextField(
                controller: _maxPlayersController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Max players',
                  isDense: true,
                  prefixIcon: Icon(Icons.groups_outlined),
                ),
              ),
            const SizedBox(height: 14),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _restrictByRating,
              onChanged: (v) => setState(() => _restrictByRating = v),
              title: const Text('Restrict by rating'),
              subtitle: const Text('Only players within a rating range can join.'),
            ),
            if (_restrictByRating) ...[
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
                'Leave one blank for an open-ended range.',
                style: TextStyle(fontSize: 11),
              ),
            ],
            if (_isDoubles) ...[
              const SizedBox(height: 14),
              Text(
                'Partner Selection',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              if (_loadingPartnerStatus)
                const Text(
                  'Checking partner status...',
                  style: TextStyle(fontSize: 11),
                )
              else if (_anyPartnershipsStarted)
                const Text(
                  'Locked — one or more players have already sent, accepted, or been assigned a partner. Unpair everyone first if you need to change this.',
                  style: TextStyle(fontSize: 11, color: AppColors.warning),
                )
              else
                const Text(
                  'Can only be changed before any partnerships have started forming.',
                  style: TextStyle(fontSize: 11),
                ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: _anyPartnershipsStarted
                      ? Colors.grey.shade200
                      : Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade400),
                  boxShadow: AppShadows.card(isDark),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: DropdownButtonFormField<String>(
                  initialValue: _partnerMode,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  items: ['host_auto', 'self_select', 'host_manual']
                      .map(
                        (mode) => DropdownMenuItem(
                          value: mode,
                          child: Text(
                            _partnerModeLabel(mode),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _anyPartnershipsStarted
                      ? null
                      : (v) => setState(() => _partnerMode = v!),
                ),
              ),
            ],
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
                    Expanded(
                      child: Text(
                        'Join code: $_joinCode',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        SharePlus.instance.share(
                          ShareParams(
                            text:
                                'Join my tournament "${_nameController.text.trim()}" on PlayMySet!\n'
                                'Join code: $_joinCode\n'
                                '(Tap this link if it opens the app: playmyset://join/$_joinCode)',
                          ),
                        );
                      },
                      child: const Icon(Icons.share_outlined, size: 18),
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
      ),
    );
  }
}
