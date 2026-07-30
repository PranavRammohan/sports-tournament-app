// pending_matches_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../api_client.dart';
import '../widgets/sport_icon.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/friendly_empty_state.dart';

class PendingMatchesScreen extends StatefulWidget {
  const PendingMatchesScreen({super.key});

  @override
  State<PendingMatchesScreen> createState() => _PendingMatchesScreenState();
}

class _PendingMatchesScreenState extends State<PendingMatchesScreen> {
  List<dynamic> _matches = [];
  bool _loading = true;
  String? _error;
  int? _currentUserId;

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
          : RefreshIndicator(
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
                        final isDoubles = m['league_format'] == 'doubles';
                        final isPlayoff = _isPlayoff(m);
                        final team1 = isDoubles
                            ? '${m['player1_username']} & ${m['player1_partner_username'] ?? '?'}'
                            : m['player1_username'];
                        final team2 = isDoubles
                            ? '${m['player2_username']} & ${m['player2_partner_username'] ?? '?'}'
                            : m['player2_username'];
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
                                            sportLabel,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: subtleTextColor,
                                            ),
                                          ),
                                          Text(
                                            '$team1 vs $team2',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                              color: primaryTextColor,
                                            ),
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
                                  ],
                                ),
                                if (_opponentContacts(m).isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  ..._opponentContacts(m).map(
                                    (c) => Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.phone,
                                            size: 12,
                                            color: subtleTextColor,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${c['name']}: ${c['phone']}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: subtleTextColor,
                                            ),
                                          ),
                                        ],
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
                                        onPressed: () => _rejectMatch(m),
                                        child: const Text(
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
                                        onPressed: () => _confirmMatch(m),
                                        child: const Text(
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
    );
  }
}
