// player_profile_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../api_client.dart';
import '../date_utils.dart';
import '../utils.dart';
import '../constants/sports.dart';
import '../widgets/sport_icon.dart';
import '../widgets/player_avatar.dart';
import '../widgets/match_badges.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/rating_sparkline.dart';
import '../widgets/win_rate_bar.dart';
import '../widgets/recent_form_strip.dart';
import '../widgets/friendly_challenge_dialog.dart';

class PlayerProfileScreen extends StatefulWidget {
  final int userId;

  const PlayerProfileScreen({super.key, required this.userId});

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  Map<String, dynamic>? _user;
  List<dynamic> _sports = [];
  List<dynamic>? _headToHead;
  List<dynamic>? _headToHeadMatches;
  int? _currentUserId;
  bool _loading = true;
  String? _error;
  // Sports both players have a singles rating for — the only ones a
  // friendly-match challenge (singles-only for now) can offer.
  List<String> _sharedSports = [];

  bool get _isOwnProfile =>
      _currentUserId != null && _currentUserId == widget.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final userJson = (await SharedPreferences.getInstance()).getString(
        'user',
      );
      if (userJson != null) {
        _currentUserId = jsonDecode(userJson)['id'];
      }

      final res = await ApiClient.get('/sports/user/${widget.userId}');

      if (res.statusCode != 200) {
        setState(() => _error = res.errorOr('Could not load this profile.'));
        return;
      }

      setState(() {
        _user = res.data['user'];
        _sports = res.data['sports'];
      });

      // Head-to-head only makes sense when viewing someone else's profile.
      if (_currentUserId != null && _currentUserId != widget.userId) {
        try {
          final h2hRes = await ApiClient.get(
            '/matches/head-to-head/${widget.userId}',
          );
          if (h2hRes.statusCode == 200) {
            setState(() {
              _headToHead = h2hRes.data['headToHead'];
              _headToHeadMatches = h2hRes.data['matches'];
            });
          }
        } catch (err) {
          // Head-to-head is a nice-to-have; don't block the rest of the
          // profile from loading if this call fails.
        }

        try {
          final mineRes = await ApiClient.get('/sports/mine');
          if (mineRes.statusCode == 200) {
            final mySports = (mineRes.data['sports'] as List<dynamic>)
                .where((s) => s['format'] == 'singles')
                .map((s) => s['sport'] as String)
                .toSet();
            final theirSports = _sports
                .where((s) => s['format'] == 'singles')
                .map((s) => s['sport'] as String)
                .toSet();
            setState(() {
              _sharedSports = mySports.intersection(theirSports).toList();
            });
          }
        } catch (err) {
          // Same as above — the challenge button just won't show.
        }
      }
    } catch (err) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _sendChallenge() async {
    final result = await showFriendlyChallengeDialog(
      context,
      opponentName: _user?['username'] ?? 'this player',
      sportOptions: _sharedSports,
    );
    if (result == null || !mounted) return;

    try {
      final res = await ApiClient.post(
        '/friendlies/challenge',
        body: {
          'opponentId': widget.userId,
          'sport': result['sport'],
          'proposedTime': result['proposedTime'],
          'venue': result['venue'],
        },
      );
      if (!mounted) return;
      if (res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Challenge sent to ${_user?['username']}!'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not send challenge.')),
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

  String _formatSportName(String sport) {
    return sport
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  Map<String, Map<String, dynamic>> _groupSportsByName() {
    final Map<String, Map<String, dynamic>> grouped = {};
    for (final row in _sports) {
      final sport = row['sport'];
      grouped.putIfAbsent(sport, () => {});
      grouped[sport]![row['format']] = row;
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_user?['username'] ?? 'Player')),
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
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          : _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final subtleTextColor = isDark
        ? Colors.grey.shade400
        : Colors.grey.shade600;
    final primaryTextColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark;
    final ratingRowBg = isDark
        ? AppColors.darkBackground
        : AppColors.background;

    final profilePicUrl = _user?['profile_pic_url'];
    final hasProfilePic = profilePicUrl != null && profilePicUrl.isNotEmpty;
    final groupedSports = _groupSportsByName();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
              boxShadow: AppShadows.card(isDark),
            ),
            child: Column(
              children: [
                PlayerAvatar(
                  username: _user?['username'] ?? '?',
                  profilePicUrl: hasProfilePic ? profilePicUrl : null,
                  radius: 30,
                  backgroundColor: Colors.white,
                ),
                const SizedBox(height: 12),
                Text(
                  _user?['username'] ?? '',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                if (_user?['location'] != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 13,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _user!['location'],
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!_isOwnProfile && _sharedSports.isNotEmpty) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _sendChallenge,
              icon: const Icon(Icons.sports_tennis, size: 18),
              label: const Text('Challenge to a friendly match'),
            ),
          ],
          if (!_isOwnProfile) ...[
            const SizedBox(height: 20),
            Text('Head-to-Head', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            _buildHeadToHeadCard(
              cardColor,
              isDark,
              primaryTextColor,
              subtleTextColor,
              ratingRowBg,
            ),
            if (_headToHeadMatches != null &&
                _headToHeadMatches!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    'Recent Matches',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(width: 10),
                  RecentFormStrip(
                    results: _headToHeadMatches!
                        .take(5)
                        .toList()
                        .reversed
                        .map(_iWonMatch)
                        .toList(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ..._headToHeadMatches!.map(
                (m) => _buildRecentMatchRow(
                  m,
                  ratingRowBg,
                  primaryTextColor,
                  subtleTextColor,
                ),
              ),
            ],
          ],
          const SizedBox(height: 20),
          Text('Sports', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          if (groupedSports.isEmpty)
            Text(
              'No sports added yet.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            ...groupedSports.entries.map((entry) {
              final sport = entry.key;
              final formats = entry.value;
              final isTableTennis = sport == 'table_tennis';
              final singles = formats['singles'];
              final doubles = formats['doubles'];

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: AppShadows.card(isDark),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          sportIcon(sport, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _formatSportName(sport),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (isTableTennis && singles != null)
                        _ratingRow(
                          'Rating',
                          singles,
                          ratingRowBg,
                          primaryTextColor,
                          subtleTextColor,
                        )
                      else ...[
                        if (singles != null)
                          _ratingRow(
                            'Singles',
                            singles,
                            ratingRowBg,
                            primaryTextColor,
                            subtleTextColor,
                          ),
                        if (singles != null && doubles != null)
                          const SizedBox(height: 8),
                        if (doubles != null)
                          _ratingRow(
                            'Doubles',
                            doubles,
                            ratingRowBg,
                            primaryTextColor,
                            subtleTextColor,
                          ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  bool _iAmSideOne(dynamic m) =>
      m['player1_id'] == _currentUserId ||
      m['player1_partner_id'] == _currentUserId;

  bool _iWonMatch(dynamic m) {
    return _iAmSideOne(m)
        ? m['winner_id'] == m['player1_id']
        : m['winner_id'] == m['player2_id'];
  }

  String _formatH2HSetScores(dynamic raw, bool iAmSideOne) {
    if (raw == null) return '';
    try {
      final List sets = jsonDecode(raw);
      if (sets.isEmpty) return '';
      return sets
          .map((s) {
            final mine = iAmSideOne ? s['me'] : s['opponent'];
            final theirs = iAmSideOne ? s['opponent'] : s['me'];
            return '$mine-$theirs';
          })
          .join(', ');
    } catch (err) {
      return '';
    }
  }

  Widget _buildRecentMatchRow(
    dynamic m,
    Color rowBg,
    Color primaryTextColor,
    Color subtleTextColor,
  ) {
    final iAmSideOne = _iAmSideOne(m);
    final iWon = _iWonMatch(m);
    final isDoublesMatch = m['format'] == 'doubles';

    final myPartnerUsername = iAmSideOne
        ? m['player1_partner_username']
        : m['player2_partner_username'];
    final theirPartnerUsername = iAmSideOne
        ? m['player2_partner_username']
        : m['player1_partner_username'];

    final myLabel = isDoublesMatch && myPartnerUsername != null
        ? 'You & $myPartnerUsername'
        : 'You';
    final theirLabel = isDoublesMatch && theirPartnerUsername != null
        ? '${_user?['username'] ?? 'Them'} & $theirPartnerUsername'
        : (_user?['username'] ?? 'Them');

    final scoreText = _formatH2HSetScores(m['set_scores'], iAmSideOne);
    final dateText = formatMatchDate(m['created_at']);
    final subtitle = [
      scoreText,
      dateText,
    ].where((s) => s.isNotEmpty).join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: rowBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          WinLossPill(won: iWon, dense: true),
          const SizedBox(width: 8),
          sportIcon(m['sport'], size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$myLabel vs $theirLabel',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: primaryTextColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 10, color: subtleTextColor),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeadToHeadCard(
    Color cardColor,
    bool isDark,
    Color primaryTextColor,
    Color subtleTextColor,
    Color rowBg,
  ) {
    if (_headToHead == null || _headToHead!.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(10),
          boxShadow: AppShadows.card(isDark),
        ),
        child: Text(
          "You haven't played any confirmed matches against ${_user?['username'] ?? 'this player'} yet.",
          style: TextStyle(fontSize: 12, color: subtleTextColor),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: AppShadows.card(isDark),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _headToHead!.asMap().entries.map((entry) {
            final index = entry.key;
            final row = entry.value;
            final sport = row['sport'];
            final format = row['format'];
            final wins = row['my_wins'];
            final losses = row['my_losses'];
            final formatLabel = format == 'doubles' ? 'Doubles' : 'Singles';
            final showFormatLabel = sport != 'table_tennis';

            return Padding(
              padding: EdgeInsets.only(
                top: index == 0 ? 0 : 10,
                bottom: index == _headToHead!.length - 1 ? 0 : 0,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: rowBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        sportIcon(sport, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          showFormatLabel
                              ? '${_formatSportName(sport)} · $formatLabel'
                              : _formatSportName(sport),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: primaryTextColor,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$wins-$losses',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 70,
                          child: WinRateBar(wins: wins, losses: losses),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _ratingRow(
    String label,
    Map<String, dynamic> data,
    Color bgColor,
    Color textColor,
    Color subtleTextColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: textColor,
                ),
              ),
              Text(
                '${data['matches_played']} matches · ${data['wins']}W ${data['losses']}L',
                style: TextStyle(fontSize: 11, color: subtleTextColor),
              ),
              if ((data['matches_played'] ?? 0) > 0) ...[
                const SizedBox(height: 4),
                SizedBox(
                  width: 90,
                  child: WinRateBar(
                    wins: data['wins'] ?? 0,
                    losses: data['losses'] ?? 0,
                  ),
                ),
              ],
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (data['matches_played'] != null && data['matches_played'] > 0) ...[
                RatingSparkline(
                  userId: widget.userId,
                  sport: data['sport'],
                  format: data['format'],
                ),
                const SizedBox(width: 10),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatRating(data['sport'], data['rating']),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.accent,
                    ),
                  ),
                  if (ratingBandFor(data['sport'], data['rating']) != null)
                    Text(
                      ratingBandFor(data['sport'], data['rating'])!,
                      style: TextStyle(fontSize: 10, color: subtleTextColor),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
