// match_history_screen.dart
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
import '../widgets/match_badges.dart';
import 'league_detail_screen.dart';

class MatchHistoryScreen extends StatefulWidget {
  const MatchHistoryScreen({super.key});

  @override
  State<MatchHistoryScreen> createState() => _MatchHistoryScreenState();
}

class _MatchHistoryScreenState extends State<MatchHistoryScreen> {
  List<dynamic> _matches = [];
  int? _currentUserId;
  bool _loading = true;
  String? _error;
  String? _filter; // null = all, 'win', 'loss'

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
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

      final res = await ApiClient.get('/matches/history');
      if (res.statusCode == 200) {
        setState(() => _matches = res.data['matches']);
      } else {
        setState(
          () => _error = res.errorOr('Could not load match history.'),
        );
      }
    } catch (err) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      setState(() => _loading = false);
    }
  }

  bool _didIWin(dynamic m) {
    final isTeam1 =
        m['player1_id'] == _currentUserId ||
        m['player1_partner_id'] == _currentUserId;
    return isTeam1
        ? m['winner_id'] == m['player1_id']
        : m['winner_id'] == m['player2_id'];
  }

  List<dynamic> get _filteredMatches {
    if (_filter == null) return _matches;
    return _matches
        .where((m) => _filter == 'win' ? _didIWin(m) : !_didIWin(m))
        .toList();
  }

  String _formatSport(String sport) => sport
      .split('_')
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  String _formatSetScores(dynamic raw) {
    try {
      final List sets = jsonDecode(raw);
      if (sets.isEmpty) return '';
      return sets.map((s) => '${s['me']}-${s['opponent']}').join(', ');
    } catch (err) {
      return '';
    }
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final matches = _filteredMatches;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Match History')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                _filterChip('All', null),
                const SizedBox(width: 8),
                _filterChip('Wins', 'win'),
                const SizedBox(width: 8),
                _filterChip('Losses', 'loss'),
              ],
            ),
          ),
          Expanded(
            child: _loading
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
                            onPressed: _loadHistory,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadHistory,
                    child: matches.isEmpty
                        ? ListView(
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.5,
                                child: FriendlyEmptyState(
                                  icon: Icons.sports_score,
                                  title: _matches.isEmpty
                                      ? "You haven't played any confirmed matches yet."
                                      : 'No matches match this filter.',
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: matches.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final m = matches[index];

                              final isTeam1 =
                                  m['player1_id'] == _currentUserId ||
                                  m['player1_partner_id'] == _currentUserId;
                              final iWon = isTeam1
                                  ? m['winner_id'] == m['player1_id']
                                  : m['winner_id'] == m['player2_id'];

                              final isDoubles =
                                  m['player1_partner_username'] != null;
                              final opponentLabel = isTeam1
                                  ? (isDoubles
                                        ? '${m['player2_username']} & ${m['player2_partner_username']}'
                                        : m['player2_username'])
                                  : (isDoubles
                                        ? '${m['player1_username']} & ${m['player1_partner_username']}'
                                        : m['player1_username']);

                              double? ratingChange;
                              if (m['player1_id'] == _currentUserId) {
                                ratingChange = _toDouble(
                                  m['player1_rating_change'],
                                );
                              } else if (m['player2_id'] == _currentUserId) {
                                ratingChange = _toDouble(
                                  m['player2_rating_change'],
                                );
                              } else if (m['player1_partner_id'] ==
                                  _currentUserId) {
                                ratingChange = _toDouble(
                                  m['player1_partner_rating_change'],
                                );
                              } else if (m['player2_partner_id'] ==
                                  _currentUserId) {
                                ratingChange = _toDouble(
                                  m['player2_partner_rating_change'],
                                );
                              }

                              final tournamentLabel =
                                  (m['league_name'] as String?) ??
                                  '${_formatSport(m['sport'])} · ${m['area']}';

                              return TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: 1),
                                duration: Duration(
                                  milliseconds:
                                      180 + (index * 30).clamp(0, 400),
                                ),
                                builder: (context, value, child) =>
                                    Opacity(opacity: value, child: child),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: m['league_id'] == null
                                        ? null
                                        : () {
                                            HapticFeedback.selectionClick();
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    LeagueDetailScreen(
                                                      leagueId: m['league_id'],
                                                    ),
                                              ),
                                            );
                                          },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 9,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).cardColor,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: AppColors.cardBorder(isDark),
                                        ),
                                        boxShadow: AppShadows.card(isDark),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 4,
                                            height: 30,
                                            decoration: BoxDecoration(
                                              color: iWon
                                                  ? AppColors.success
                                                  : AppColors.danger,
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          sportIcon(m['sport'], size: 16),
                                          const SizedBox(width: 8),
                                          SizedBox(
                                            width: 34,
                                            child: Text(
                                              iWon ? 'WIN' : 'LOSS',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: iWon
                                                    ? AppColors.success
                                                    : AppColors.danger,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'vs $opponentLabel',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 13,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  '$tournamentLabel · ${_formatSetScores(m['set_scores'])} · ${formatMatchDate(m['created_at'])}',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: AppColors.textGrey,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                          RatingDeltaText(delta: ratingChange),
                                          if (m['league_id'] != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                left: 4,
                                              ),
                                              child: Icon(
                                                Icons.chevron_right,
                                                size: 16,
                                                color: Colors.grey.shade400,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
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

  Widget _filterChip(String label, String? value) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) {
        HapticFeedback.selectionClick();
        setState(() => _filter = value);
      },
      selectedColor: AppColors.primary.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: selected ? AppColors.primary : Colors.grey.shade700,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}
