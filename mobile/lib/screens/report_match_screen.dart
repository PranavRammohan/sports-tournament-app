// report_match_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../api_client.dart';
import '../validators.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/friendly_empty_state.dart';
import '../widgets/match_photo_picker.dart';

class ReportMatchScreen extends StatefulWidget {
  final int leagueId;
  final String format;
  final String sport;
  final List<dynamic> members;
  // When set, fixtures are loaded from this group's own schedule instead of
  // the whole league's — without this, a player in more than one group
  // (nested groups allow that) could be shown a fixture from a different
  // group than the one they tapped Report from, one that doesn't appear in
  // that group's own Schedule/My Matches view at all.
  final int? groupId;

  const ReportMatchScreen({
    super.key,
    required this.leagueId,
    required this.format,
    required this.sport,
    required this.members,
    this.groupId,
  });

  @override
  State<ReportMatchScreen> createState() => _ReportMatchScreenState();
}

class _SetScore {
  final TextEditingController myScore = TextEditingController();
  final TextEditingController opponentScore = TextEditingController();
}

class _ReportMatchScreenState extends State<ReportMatchScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loadingFixtures = true;
  bool _scheduleExists = false;
  String? _loadError;
  List<dynamic> _myPendingFixtures = [];
  int? _currentUserId;

  Map<String, dynamic>? _selectedFixture;
  int? _opponentId;
  int? _partnerId;
  int? _opponentPartnerId;

  final List<_SetScore> _sets = [_SetScore()];
  bool _submitting = false;

  // GAP-17 — an optional scorecard photo, attached the same base64
  // data-URI way as a profile picture. Picker UI lives in the shared
  // MatchPhotoPicker widget, used by every report/edit dialog in the app.
  String? _photoDataUri;

  String get _unitLabel => widget.sport == 'tennis' ? 'Set' : 'Game';

  @override
  void initState() {
    super.initState();
    _loadFixtures();
  }

  Future<void> _loadFixtures() async {
    setState(() {
      _loadingFixtures = true;
      _loadError = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('user');
      if (userJson != null) {
        _currentUserId = jsonDecode(userJson)['id'];
      }

      final res = await ApiClient.get(
        widget.groupId != null
            ? '/leagues/${widget.leagueId}/groups/${widget.groupId}/schedule'
            : '/leagues/${widget.leagueId}/schedule',
      );

      if (res.statusCode == 200) {
        final List allFixtures = res.data['schedule'];
        setState(() => _scheduleExists = allFixtures.isNotEmpty);

        final myFixtures = allFixtures.where((f) {
          final involved = [
            f['player1_id'],
            f['player1_partner_id'],
            f['player2_id'],
            f['player2_partner_id'],
          ];
          final notCompleted = f['match_status'] != 'confirmed';
          return involved.contains(_currentUserId) && notCompleted;
        }).toList();

        setState(() => _myPendingFixtures = myFixtures);
      } else {
        // A real fetch failure — distinct from "there's genuinely no
        // schedule yet" — must not silently fall through to free-pick mode.
        setState(
          () => _loadError = res.errorOr('Could not load the schedule.'),
        );
      }
    } catch (err) {
      setState(() => _loadError = 'Could not reach the server.');
    } finally {
      setState(() => _loadingFixtures = false);
    }
  }

  String? _ratingFor(int? playerId) {
    if (playerId == null) return null;
    for (final m in widget.members) {
      if (m['id'] == playerId) return '${m['rating']}';
    }
    return null;
  }

  void _selectFixture(Map<String, dynamic> fixture) {
    HapticFeedback.selectionClick();
    final iAmTeam1 =
        fixture['player1_id'] == _currentUserId ||
        fixture['player1_partner_id'] == _currentUserId;

    setState(() {
      _selectedFixture = fixture;
      if (iAmTeam1) {
        _opponentId = fixture['player2_id'];
        _opponentPartnerId = fixture['player2_partner_id'];
        _partnerId = fixture['player1_partner_id'] == _currentUserId
            ? fixture['player1_id']
            : fixture['player1_partner_id'];
      } else {
        _opponentId = fixture['player1_id'];
        _opponentPartnerId = fixture['player1_partner_id'];
        _partnerId = fixture['player2_partner_id'] == _currentUserId
            ? fixture['player2_id']
            : fixture['player2_partner_id'];
      }
    });
  }

  String _fixtureOpponentLabel(Map<String, dynamic> fixture) {
    final iAmTeam1 =
        fixture['player1_id'] == _currentUserId ||
        fixture['player1_partner_id'] == _currentUserId;
    if (iAmTeam1) {
      final isDoubles = fixture['player2_partner_username'] != null;
      final opponentRating = _ratingFor(fixture['player2_id']);
      final label = isDoubles
          ? '${fixture['player2_username']} & ${fixture['player2_partner_username']}'
          : fixture['player2_username'];
      return isDoubles || opponentRating == null
          ? label
          : '$label ($opponentRating)';
    } else {
      final isDoubles = fixture['player1_partner_username'] != null;
      final opponentRating = _ratingFor(fixture['player1_id']);
      final label = isDoubles
          ? '${fixture['player1_username']} & ${fixture['player1_partner_username']}'
          : fixture['player1_username'];
      return isDoubles || opponentRating == null
          ? label
          : '$label ($opponentRating)';
    }
  }

  static const int _maxSets = 7;

  void _addSet() {
    if (_sets.length >= _maxSets) return;
    HapticFeedback.selectionClick();
    setState(() => _sets.add(_SetScore()));
  }

  void _removeSet(int index) {
    if (_sets.length > 1) {
      HapticFeedback.selectionClick();
      setState(() => _sets.removeAt(index));
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_opponentId == null) {
      _showAlert('Missing info', 'Please select a match to report.');
      return;
    }
    if (widget.format == 'doubles' &&
        (_partnerId == null || _opponentPartnerId == null)) {
      _showAlert(
        'Missing info',
        'Doubles matches need both partners selected.',
      );
      return;
    }

    final allSelected = [_currentUserId, _partnerId, _opponentId, _opponentPartnerId]
        .whereType<int>()
        .toList();
    if (allSelected.toSet().length != allSelected.length) {
      _showAlert(
        'Duplicate selection',
        'The same player cannot appear twice in one match.',
      );
      return;
    }

    int totalMyUnits = 0;
    int totalOpponentUnits = 0;
    int setsWonByMe = 0;
    int setsWonByOpponent = 0;
    final List<Map<String, int>> setScores = [];

    for (final s in _sets) {
      final my = int.tryParse(s.myScore.text.trim());
      final opp = int.tryParse(s.opponentScore.text.trim());
      if (my == null || opp == null) {
        _showAlert('Missing scores', 'Please fill in every $_unitLabel score.');
        return;
      }
      if (my == opp) {
        _showAlert('Invalid score', 'A $_unitLabel cannot end in a tie.');
        return;
      }
      setScores.add({'me': my, 'opponent': opp});
      totalMyUnits += my;
      totalOpponentUnits += opp;
      if (my > opp) {
        setsWonByMe++;
      } else {
        setsWonByOpponent++;
      }
    }

    if (setsWonByMe == setsWonByOpponent) {
      _showAlert('Invalid result', 'The match needs an overall winner.');
      return;
    }

    final iWon = setsWonByMe > setsWonByOpponent;

    HapticFeedback.lightImpact();
    setState(() => _submitting = true);

    try {
      final res = await ApiClient.post(
        '/matches/report',
        body: {
          'leagueId': widget.leagueId,
          'opponentId': _opponentId,
          'partnerId': _partnerId,
          'opponentPartnerId': _opponentPartnerId,
          'myUnits': totalMyUnits,
          'opponentUnits': totalOpponentUnits,
          'iWon': iWon,
          'setScores': setScores,
          if (_photoDataUri != null) 'photoUrl': _photoDataUri,
        },
      );

      if (res.statusCode != 201) {
        _showAlert('Something went wrong', res.errorOr('Please try again.'));
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

  @override
  Widget build(BuildContext context) {
    if (_loadingFixtures) {
      return Scaffold(
        appBar: AppBar(title: const Text('Report Match')),
        body: const SkeletonList(),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Report Match')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _loadFixtures,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // No scheduled fixtures exist anywhere in this league/group yet — e.g. a
    // 'custom' league before the host has added a manual match, or a
    // round-robin league before the schedule's been generated. The backend
    // unconditionally requires a matching scheduled fixture to self-report
    // (see matchRoutes.js's POST /report), so there is nothing reportable
    // here — showing a free-pick "any opponent" form in this state used to
    // look functional but always failed on submit.
    if (!_scheduleExists) {
      return Scaffold(
        appBar: AppBar(title: const Text('Report Match')),
        body: const FriendlyEmptyState(
          icon: Icons.calendar_today_outlined,
          title: 'Nothing to report yet',
          subtitle:
              "The host hasn't set up a schedule or added any matches yet — check back once they have.",
        ),
      );
    }

    if (_myPendingFixtures.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Report Match')),
        body: const FriendlyEmptyState(
          icon: Icons.check_circle_outline,
          title: 'All caught up',
          subtitle: "You don't have any pending scheduled matches left to report.",
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final unselectedBorder = isDark
        ? Colors.grey.shade600
        : Colors.grey.shade300;
    final unselectedIconColor = isDark
        ? Colors.grey.shade500
        : Colors.grey.shade400;
    final titleColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark;
    final tierChipBg = isDark ? Colors.grey.shade800 : Colors.grey.shade100;

    return Scaffold(
      appBar: AppBar(title: const Text('Report Match')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Select your scheduled match',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            ..._myPendingFixtures.map((fixture) {
                final selected =
                    _selectedFixture != null &&
                    _selectedFixture!['id'] == fixture['id'];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _selectFixture(fixture),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary.withValues(
                                alpha: isDark ? 0.18 : 0.06,
                              )
                            : cardColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : unselectedBorder,
                          width: selected ? 2 : 1,
                        ),
                        boxShadow: AppShadows.card(isDark),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: selected
                                ? AppColors.primary
                                : unselectedIconColor,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'vs ${_fixtureOpponentLabel(fixture)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: titleColor,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: tierChipBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Tier ${fixture['tier_number']}',
                              style: TextStyle(fontSize: 11, color: titleColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            const SizedBox(height: 24),
            Text(
              '$_unitLabel Scores',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ..._sets.asMap().entries.map((entry) {
              final index = entry.key;
              final set = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: set.myScore,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        validator: (v) =>
                            nonNegativeIntValidator(v, label: '$_unitLabel score'),
                        decoration: InputDecoration(
                          labelText: '$_unitLabel ${index + 1} — You',
                          isDense: true,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('-'),
                    ),
                    Expanded(
                      child: TextFormField(
                        controller: set.opponentScore,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        validator: (v) =>
                            nonNegativeIntValidator(v, label: '$_unitLabel score'),
                        decoration: const InputDecoration(
                          labelText: 'Opponent',
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_sets.length > 1)
                      IconButton(
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          color: AppColors.danger,
                        ),
                        tooltip: 'Remove $_unitLabel ${index + 1}',
                        onPressed: () => _removeSet(index),
                      ),
                  ],
                ),
              );
            }),
            if (_sets.length < _maxSets)
              TextButton.icon(
                onPressed: _addSet,
                icon: const Icon(Icons.add),
                label: Text('Add $_unitLabel'),
              ),
            const SizedBox(height: 20),
            Text(
              'Scorecard Photo (optional)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            MatchPhotoPicker(
              onChanged: (dataUri) => setState(() => _photoDataUri = dataUri),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _submitting ? null : _handleSubmit,
              child: _submitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text('Submit Result'),
            ),
          ],
          ),
        ),
      ),
    );
  }
}
