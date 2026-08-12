// pending_matches_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../api_client.dart';
import '../date_utils.dart';
import '../widgets/sport_icon.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/friendly_empty_state.dart';
import '../widgets/match_photo_thumbnail.dart';
import '../widgets/team_name_row.dart';
import '../utils.dart';

class PendingMatchesScreen extends StatefulWidget {
  // Lets MainShell keep its bottom-nav badge count in sync the moment a
  // match is confirmed/rejected here, instead of only refreshing when the
  // user happens to switch tabs.
  final VoidCallback? onPendingChanged;

  const PendingMatchesScreen({super.key, this.onPendingChanged});

  @override
  State<PendingMatchesScreen> createState() => _PendingMatchesScreenState();
}

class _PendingMatchesScreenState extends State<PendingMatchesScreen> {
  List<dynamic> _matches = [];
  bool _loading = true;
  String? _error;
  int? _currentUserId;
  // Ids of matches currently being confirmed/rejected — disables just that
  // row's buttons so a slow connection can't be double-tapped into a second
  // confirm/reject request, matching the pattern in add_players_screen.dart.
  final Set<dynamic> _actingIds = {};

  // Friendly-match challenges — a separate table/endpoint from tournament
  // matches (see backend/friendlyRoutes.js), so fetched and rendered as
  // their own section rather than merged into _matches.
  List<dynamic> _friendlyIncoming = [];
  List<dynamic> _friendlyOutgoing = [];
  List<dynamic> _friendlyAccepted = [];
  final Set<dynamic> _friendlyActingIds = {};

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  void refresh() {
    _loadMatches();
  }

  Future<void> _loadMatches() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('user');
      if (userJson != null) {
        _currentUserId = jsonDecode(userJson)['id'];
      }

      final res = await ApiClient.get('/matches/pending');
      if (res.statusCode == 200) {
        setState(() => _matches = res.data['matches']);
      } else {
        setState(
          () => _error = res.errorOr('Could not load pending matches.'),
        );
      }

      try {
        final friendlyRes = await ApiClient.get('/friendlies/pending');
        if (friendlyRes.statusCode == 200) {
          setState(() {
            _friendlyIncoming = friendlyRes.data['incoming'];
            _friendlyOutgoing = friendlyRes.data['outgoing'];
            _friendlyAccepted = friendlyRes.data['accepted'];
          });
        }
      } catch (err) {
        // Friendly challenges are a secondary section — don't let a failure
        // here block the tournament-matches list from loading.
      }
    } catch (err) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      setState(() => _loading = false);
    }
  }

  // matchType is 'regular' (round-robin/custom matches) or 'playoff'
  // (knockout bracket matches) — the backend now returns both kinds merged
  // together in /matches/pending, tagged with this field, since knockout
  // reports live in a separate table with separate confirm/reject endpoints.
  bool _isPlayoff(dynamic m) => m['match_type'] == 'playoff';

  Future<void> _confirmMatch(dynamic m) async {
    HapticFeedback.lightImpact();
    setState(() => _actingIds.add(m['id']));
    try {
      final path = _isPlayoff(m)
          ? '/playoffs/match/${m['id']}/confirm'
          : '/matches/${m['id']}/confirm';

      final res = await ApiClient.post(path);

      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Match confirmed! Ratings updated.'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadMatches();
        widget.onPendingChanged?.call();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not confirm.')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Network error.')));
    } finally {
      if (mounted) setState(() => _actingIds.remove(m['id']));
    }
  }

  Future<void> _rejectMatch(dynamic m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('Reject this result?'),
        content: const Text(
          'The reporter can submit the correct score again afterward.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Reject',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    HapticFeedback.mediumImpact();
    setState(() => _actingIds.add(m['id']));
    try {
      final path = _isPlayoff(m)
          ? '/playoffs/match/${m['id']}/reject'
          : '/matches/${m['id']}/reject';

      final res = await ApiClient.post(path);

      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Match rejected.'),
            backgroundColor: AppColors.warning,
          ),
        );
        _loadMatches();
        widget.onPendingChanged?.call();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not reject.')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Network error.')));
    } finally {
      if (mounted) setState(() => _actingIds.remove(m['id']));
    }
  }

  Future<void> _respondFriendly(dynamic challenge, bool accept) async {
    HapticFeedback.lightImpact();
    setState(() => _friendlyActingIds.add(challenge['id']));
    try {
      final res = await ApiClient.post(
        '/friendlies/${challenge['id']}/respond',
        body: {'accept': accept},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(accept ? 'Challenge accepted!' : 'Challenge declined.'),
            backgroundColor: accept ? AppColors.success : AppColors.warning,
          ),
        );
        _loadMatches();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not respond to the challenge.')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Network error.')));
    } finally {
      if (mounted) setState(() => _friendlyActingIds.remove(challenge['id']));
    }
  }

  Future<void> _cancelFriendly(dynamic challenge) async {
    HapticFeedback.lightImpact();
    setState(() => _friendlyActingIds.add(challenge['id']));
    try {
      final res = await ApiClient.delete('/friendlies/${challenge['id']}');
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Challenge cancelled.'),
            backgroundColor: AppColors.warning,
          ),
        );
        _loadMatches();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not cancel the challenge.')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Network error.')));
    } finally {
      if (mounted) setState(() => _friendlyActingIds.remove(challenge['id']));
    }
  }

  Future<void> _reportFriendly(dynamic f) async {
    final isPlayer1 = f['player1_id'] == _currentUserId;
    final myName = isPlayer1 ? f['player1_username'] : f['player2_username'];
    final opponentName = isPlayer1 ? f['player2_username'] : f['player1_username'];

    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (ctx) => _FriendlyScoreDialog(
        myName: myName,
        opponentName: opponentName,
      ),
    );
    if (result == null) return;

    final myUnits = result['me']!;
    final opponentUnits = result['opponent']!;
    final player1Units = isPlayer1 ? myUnits : opponentUnits;
    final player2Units = isPlayer1 ? opponentUnits : myUnits;
    final iWon = myUnits > opponentUnits;
    final winnerId = iWon
        ? _currentUserId
        : (isPlayer1 ? f['player2_id'] : f['player1_id']);

    HapticFeedback.lightImpact();
    setState(() => _friendlyActingIds.add(f['id']));
    try {
      final res = await ApiClient.post(
        '/friendlies/${f['id']}/report',
        body: {
          'player1Units': player1Units,
          'player2Units': player2Units,
          'setScores': [],
          'winnerId': winnerId,
        },
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Result recorded!'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadMatches();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not record the result.')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Network error.')));
    } finally {
      if (mounted) setState(() => _friendlyActingIds.remove(f['id']));
    }
  }

  String _formatSport(String sport) => sport
      .split('_')
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  String _formatSetScores(dynamic raw, bool reportedByPlayer1) {
    try {
      final List sets = jsonDecode(raw);
      if (sets.isEmpty) return '';
      return sets
          .map((s) {
            final mine = s['me'];
            final theirs = s['opponent'];
            return reportedByPlayer1 ? '$mine-$theirs' : '$theirs-$mine';
          })
          .join(', ');
    } catch (err) {
      return '';
    }
  }

  // Since /matches/pending only ever returns matches where the current user
  // is the one who needs to confirm (not the reporter), the "opponent" here
  // is always the reporter's side — surface their contact info the same way
  // the in-tournament schedule view already does.
  List<Map<String, String>> _opponentContacts(dynamic m) {
    final iAmPlayer1Side =
        m['player1_id'] == _currentUserId ||
        m['player1_partner_id'] == _currentUserId;
    final contacts = <Map<String, String>>[];

    if (iAmPlayer1Side) {
      if (m['player2_phone'] != null) {
        contacts.add({
          'name': m['player2_username'],
          'phone': m['player2_phone'],
        });
      }
      if (m['player2_partner_phone'] != null) {
        contacts.add({
          'name': m['player2_partner_username'],
          'phone': m['player2_partner_phone'],
        });
      }
    } else {
      if (m['player1_phone'] != null) {
        contacts.add({
          'name': m['player1_username'],
          'phone': m['player1_phone'],
        });
      }
      if (m['player1_partner_phone'] != null) {
        contacts.add({
          'name': m['player1_partner_username'],
          'phone': m['player1_partner_phone'],
        });
      }
    }
    return contacts;
  }

  Widget _buildFriendlySection(
    Color cardColor,
    bool isDark,
    Color primaryTextColor,
    Color subtleTextColor,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
        boxShadow: AppShadows.card(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sports_tennis, size: 18, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(
                'Friendly Matches',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: primaryTextColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._friendlyIncoming.map((c) {
            final isActing = _friendlyActingIds.contains(c['id']);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${c['player1_username']} challenged you · ${_formatSport(c['sport'])}',
                      style: TextStyle(fontSize: 13, color: primaryTextColor),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.check_circle, color: AppColors.success),
                    tooltip: 'Accept',
                    onPressed: isActing ? null : () => _respondFriendly(c, true),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel, color: AppColors.danger),
                    tooltip: 'Decline',
                    onPressed: isActing ? null : () => _respondFriendly(c, false),
                  ),
                ],
              ),
            );
          }),
          ..._friendlyOutgoing.map((c) {
            final isActing = _friendlyActingIds.contains(c['id']);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Waiting on ${c['player2_username']} · ${_formatSport(c['sport'])}',
                      style: TextStyle(fontSize: 13, color: subtleTextColor),
                    ),
                  ),
                  TextButton(
                    onPressed: isActing ? null : () => _cancelFriendly(c),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            );
          }),
          ..._friendlyAccepted.map((f) {
            final isActing = _friendlyActingIds.contains(f['id']);
            final isPlayer1 = f['player1_id'] == _currentUserId;
            final opponentName =
                isPlayer1 ? f['player2_username'] : f['player1_username'];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'vs $opponentName · ${_formatSport(f['sport'])} — accepted',
                      style: TextStyle(fontSize: 13, color: primaryTextColor),
                    ),
                  ),
                  TextButton(
                    onPressed: isActing ? null : () => _reportFriendly(f),
                    child: const Text('Report Score'),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final subtleTextColor = isDark
        ? Colors.grey.shade400
        : Colors.grey.shade700;
    final primaryTextColor = isDark ? Colors.white : AppColors.textDark;

    return Scaffold(
      appBar: AppBar(title: const Text('Pending Confirmations')),
      body: _loading
          ? const SkeletonList()
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _loadMatches,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                if (_friendlyIncoming.isNotEmpty ||
                    _friendlyOutgoing.isNotEmpty ||
                    _friendlyAccepted.isNotEmpty)
                  _buildFriendlySection(
                    cardColor,
                    isDark,
                    primaryTextColor,
                    subtleTextColor,
                  ),
                Expanded(
                  child: RefreshIndicator(
              onRefresh: _loadMatches,
              child: _matches.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.5,
                          child: const FriendlyEmptyState(
                            icon: Icons.check_circle_outline,
                            title: 'Nothing waiting on you right now.',
                            subtitle: "You're all caught up!",
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _matches.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final m = _matches[index];
                        final isActing = _actingIds.contains(m['id']);
                        final isPlayoff = _isPlayoff(m);
                        final reportedByPlayer1 =
                            m['reported_by'] == m['player1_id'];
                        final sportLabel = isPlayoff
                            ? '${_formatSport(m['sport'])} · Knockout${m['round_number'] != null ? ' · Round ${m['round_number']}' : ''}'
                            : _formatSport(m['sport']);

                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: Duration(
                            milliseconds: 180 + (index * 30).clamp(0, 400),
                          ),
                          builder: (context, value, child) =>
                              Opacity(opacity: value, child: child),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.warning.withValues(alpha: 0.4),
                              ),
                              boxShadow: AppShadows.card(isDark),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    sportIcon(m['sport'], size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '$sportLabel · ${formatRelativeTime(m['created_at'])}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: subtleTextColor,
                                            ),
                                          ),
                                          Row(
                                            children: [
                                              Flexible(
                                                child: TeamNameRow(
                                                  playerId: m['player1_id'],
                                                  playerName:
                                                      m['player1_username'] ??
                                                      '',
                                                  partnerId:
                                                      m['player1_partner_id'],
                                                  partnerName:
                                                      m['player1_partner_username'],
                                                  style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    fontSize: 13,
                                                    color: primaryTextColor,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                ' vs ',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                  color: primaryTextColor,
                                                ),
                                              ),
                                              Flexible(
                                                child: TeamNameRow(
                                                  playerId: m['player2_id'],
                                                  playerName:
                                                      m['player2_username'] ??
                                                      '',
                                                  partnerId:
                                                      m['player2_partner_id'],
                                                  partnerName:
                                                      m['player2_partner_username'],
                                                  style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    fontSize: 13,
                                                    color: primaryTextColor,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            _formatSetScores(
                                              m['set_scores'],
                                              reportedByPlayer1,
                                            ),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: subtleTextColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (m['photo_url'] != null) ...[
                                      const SizedBox(width: 8),
                                      MatchPhotoThumbnail(
                                        photoUrl: m['photo_url'],
                                      ),
                                    ],
                                  ],
                                ),
                                if (_opponentContacts(m).isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  ..._opponentContacts(m).map(
                                    (c) => Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: InkWell(
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          launchPhoneCall(c['phone'] as String);
                                        },
                                        borderRadius: BorderRadius.circular(4),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.phone,
                                              size: 12,
                                              color: AppColors.primaryLight,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${c['name']}: ${c['phone']}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: AppColors.primaryLight,
                                                decoration: TextDecoration.underline,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.danger,
                                          side: const BorderSide(
                                            color: AppColors.danger,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                        ),
                                        onPressed: isActing
                                            ? null
                                            : () => _rejectMatch(m),
                                        child: isActing
                                            ? const SizedBox(
                                                height: 14,
                                                width: 14,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: AppColors.danger,
                                                ),
                                              )
                                            : const Text(
                                                'Reject',
                                                style: TextStyle(fontSize: 13),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                        ),
                                        onPressed: isActing
                                            ? null
                                            : () => _confirmMatch(m),
                                        child: isActing
                                            ? const SizedBox(
                                                height: 14,
                                                width: 14,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : const Text(
                                                'Confirm',
                                                style: TextStyle(fontSize: 13),
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// Simple score entry for a friendly match — a single units total per side
// rather than the full multi-set breakdown host-reported tournament matches
// use, since a friendly is casual and the units are only ever shown back to
// the two players themselves. Winner is derived from whichever side scored
// higher (the backend's winnerUnitsAreConsistent check rejects a mismatch).
class _FriendlyScoreDialog extends StatefulWidget {
  final String myName;
  final String opponentName;

  const _FriendlyScoreDialog({
    required this.myName,
    required this.opponentName,
  });

  @override
  State<_FriendlyScoreDialog> createState() => _FriendlyScoreDialogState();
}

class _FriendlyScoreDialogState extends State<_FriendlyScoreDialog> {
  final TextEditingController _myController = TextEditingController();
  final TextEditingController _opponentController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _myController.dispose();
    _opponentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: const Text('Report Friendly Result'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _myController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: widget.myName),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('-'),
              ),
              Expanded(
                child: TextField(
                  controller: _opponentController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: widget.opponentName),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final my = int.tryParse(_myController.text.trim());
            final opponent = int.tryParse(_opponentController.text.trim());
            if (my == null || opponent == null) {
              setState(() => _error = 'Please fill in both scores.');
              return;
            }
            if (my == opponent) {
              setState(() => _error = 'The match needs a winner.');
              return;
            }
            Navigator.pop(context, {'me': my, 'opponent': opponent});
          },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
