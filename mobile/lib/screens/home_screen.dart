// home_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../api_client.dart';
import '../utils.dart';
import '../widgets/sport_icon.dart';
import '../widgets/player_avatar.dart';
import '../widgets/match_badges.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/friendly_empty_state.dart';
import '../widgets/win_rate_bar.dart';
import '../widgets/team_name_row.dart';
import '../widgets/rating_scale_bar.dart';
import 'add_sport_screen.dart';
import 'my_leagues_screen.dart';
import 'match_history_screen.dart';
import 'pending_matches_screen.dart';
import 'league_detail_screen.dart';
import 'notifications_screen.dart';
import 'find_players_screen.dart';

class HomeScreen extends StatefulWidget {
  // Owned by MainShell so the badge count stays live across tab switches —
  // see main_shell.dart's _loadUnreadNotifCount for why this can't just be
  // fetched once inside HomeScreen itself (Pending's badge lives directly in
  // MainShell's own NavigationBar for the same reason; this is the version
  // of that for a per-screen AppBar action instead of a nav destination).
  final int unreadNotifCount;
  final VoidCallback? onNotificationsChanged;

  const HomeScreen({
    super.key,
    this.unreadNotifCount = 0,
    this.onNotificationsChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _username = '';
  int _leagueCount = 0;
  int _matchesPlayed = 0;
  int _wins = 0;
  Map<String, Map<String, dynamic>> _sportsGrouped = {};
  List<dynamic> _pendingMatches = [];
  List<dynamic> _upcomingMatches = [];
  Map<String, dynamic>? _recentMatch;
  int? _currentUserId;
  String? _profilePicUrl;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEverything();
  }

  void refresh() {
    _loadEverything();
  }

  Future<void> _loadEverything() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('user');
      if (userJson != null) {
        final userData = jsonDecode(userJson);
        _username = userData['username'] ?? '';
        _currentUserId = userData['id'];
      }

      Future<ApiResponse?> fetchProfilePic() async {
        if (_currentUserId == null) return null;
        try {
          return await ApiClient.get('/sports/user/$_currentUserId');
        } catch (err) {
          // Non-critical — the welcome card just falls back to an initial.
          return null;
        }
      }

      // Fire the profile-pic fetch and the four core fetches concurrently —
      // none of these depend on each other's results.
      final profileFuture = fetchProfilePic();
      final coreResults = await Future.wait([
        ApiClient.get('/leagues/mine'),
        ApiClient.get('/sports/mine'),
        ApiClient.get('/matches/pending'),
        ApiClient.get('/matches/upcoming'),
        ApiClient.get('/matches/history'),
      ]);
      final profileRes = await profileFuture;
      final leaguesRes = coreResults[0];
      final sportsRes = coreResults[1];
      final pendingRes = coreResults[2];
      final upcomingRes = coreResults[3];
      final historyRes = coreResults[4];

      if (profileRes != null && profileRes.statusCode == 200) {
        _profilePicUrl = profileRes.data['user']?['profile_pic_url'];
      }

      if (leaguesRes.statusCode == 200) {
        _leagueCount = (leaguesRes.data['leagues'] as List).length;
      }

      if (sportsRes.statusCode == 200) {
        // IMPORTANT: aggregate matches/wins from the RAW rows, before any
        // grouping. A sport like badminton can have both a singles row and
        // a doubles row — both are shown in "Your Sports" below, but the
        // grouping step must not affect these totals.
        final List rawSports = sportsRes.data['sports'];
        _matchesPlayed = rawSports.fold<int>(
          0,
          (sum, r) => sum + (r['matches_played'] as int),
        );
        _wins = rawSports.fold<int>(0, (sum, r) => sum + (r['wins'] as int));

        final Map<String, Map<String, dynamic>> grouped = {};
        for (final row in rawSports) {
          final sport = row['sport'];
          grouped.putIfAbsent(sport, () => {});
          grouped[sport]![row['format']] = row;
        }
        _sportsGrouped = grouped;
      }

      if (pendingRes.statusCode == 200) {
        _pendingMatches = pendingRes.data['matches'];
      }

      if (upcomingRes.statusCode == 200) {
        _upcomingMatches = upcomingRes.data['upcoming'];
      }

      if (historyRes.statusCode == 200 &&
          (historyRes.data['matches'] as List).isNotEmpty) {
        _recentMatch = historyRes.data['matches'][0];
      }
    } catch (err) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      setState(() => _loading = false);
    }
  }

  String _formatSportName(String sport) {
    return sport
        .split('_')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  // The opposing side's name(s), as a tappable TeamNameRow rather than a
  // plain string — each of these cards is itself wrapped in its own InkWell
  // (to open match history / the tournament), but Flutter resolves the
  // nested tap correctly: tapping the name opens that player's profile,
  // tapping anywhere else on the card falls through to the outer action.
  Widget _opponentTeamNameRow(dynamic m, int? currentUserId, TextStyle style) {
    final isTeam1 =
        m['player1_id'] == currentUserId ||
        m['player1_partner_id'] == currentUserId;
    return TeamNameRow(
      playerId: isTeam1 ? m['player2_id'] : m['player1_id'],
      playerName:
          (isTeam1 ? m['player2_username'] : m['player1_username']) ?? '',
      partnerId: isTeam1
          ? m['player2_partner_id']
          : m['player1_partner_id'],
      partnerName: isTeam1
          ? m['player2_partner_username']
          : m['player1_partner_username'],
      style: style,
    );
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final winRate = _matchesPlayed == 0
        ? 0
        : ((_wins / _matchesPlayed) * 100).round();
    final losses = _matchesPlayed - _wins;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final borderColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    final subtleTextColor = isDark
        ? Colors.grey.shade400
        : Colors.grey.shade600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PlayMySet'),
        actions: [
          IconButton(
            tooltip: 'Find Players',
            icon: const Icon(Icons.person_search),
            onPressed: () {
              HapticFeedback.selectionClick();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FindPlayersScreen()),
              );
            },
          ),
          IconButton(
            tooltip: widget.unreadNotifCount > 0
                ? '${widget.unreadNotifCount} unread notifications'
                : 'Notifications',
            icon: widget.unreadNotifCount > 0
                ? Badge(
                    label: Text('${widget.unreadNotifCount}'),
                    backgroundColor: AppColors.danger,
                    child: const Icon(Icons.notifications_outlined),
                  )
                : const Icon(Icons.notifications_outlined),
            onPressed: () async {
              HapticFeedback.selectionClick();
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
              widget.onNotificationsChanged?.call();
            },
          ),
        ],
      ),
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
                      onPressed: _loadEverything,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadEverything,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: AppShadows.card(isDark),
                    ),
                    child: Row(
                      children: [
                        PlayerAvatar(
                          username: _username,
                          profilePicUrl: _profilePicUrl,
                          radius: 26,
                          backgroundColor: Colors.white,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Welcome back',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                              Text(
                                _username,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: _statCard(
                          Icons.list_alt,
                          'Tournaments',
                          '$_leagueCount',
                          cardColor,
                          borderColor,
                          subtleTextColor,
                          isDark,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MyLeaguesScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statCard(
                          Icons.sports_score,
                          'Matches',
                          '$_matchesPlayed',
                          cardColor,
                          borderColor,
                          subtleTextColor,
                          isDark,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MatchHistoryScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statCard(
                          Icons.emoji_events,
                          'Win rate',
                          '$winRate% ($_wins-$losses)',
                          cardColor,
                          borderColor,
                          subtleTextColor,
                          isDark,
                          barWins: _wins,
                          barLosses: losses,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MatchHistoryScreen(),
                              ),
                            );
                          },
                          smallValue: true,
                        ),
                      ),
                    ],
                  ),

                  if (_pendingMatches.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PendingMatchesScreen(),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(
                            alpha: isDark ? 0.15 : 0.1,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.pending_actions,
                              color: AppColors.warning,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _pendingMatches.length == 1
                                    ? '1 match is waiting on your confirmation'
                                    : '${_pendingMatches.length} matches are waiting on your confirmation',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color:
                                      Theme.of(
                                        context,
                                      ).textTheme.bodyLarge?.color ??
                                      AppColors.textDark,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              color: AppColors.warning,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  if (_recentMatch != null) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Last Match',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    _buildRecentMatchCard(cardColor, subtleTextColor, isDark),
                  ],

                  if (_sportsGrouped.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Your Sports',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    ..._sportsGrouped.entries.map(
                      (entry) => _buildSportSummaryRow(
                        entry.key,
                        entry.value,
                        cardColor,
                        borderColor,
                        isDark,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 20),
                    FriendlyEmptyState(
                      icon: Icons.sports_tennis,
                      title: 'Add a sport to get started',
                      subtitle:
                          'Once you add a sport, your matches and tournaments will show up here.',
                      actionLabel: 'Add a sport',
                      onAction: () async {
                        HapticFeedback.selectionClick();
                        final added = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const AddSportScreen(existingSports: []),
                          ),
                        );
                        if (added == true) _loadEverything();
                      },
                    ),
                  ],

                  if (_upcomingMatches.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Upcoming Matches',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    ..._upcomingMatches.map(
                      (m) => _buildUpcomingMatchRow(
                        m,
                        cardColor,
                        borderColor,
                        subtleTextColor,
                        isDark,
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),
                ],
              ),
            ),
    );
  }

  Widget _statCard(
    IconData icon,
    String label,
    String value,
    Color cardColor,
    Color borderColor,
    Color subtleTextColor,
    bool isDark, {
    required VoidCallback onTap,
    bool smallValue = false,
    int? barWins,
    int? barLosses,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
          boxShadow: AppShadows.card(isDark),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: AppColors.accent),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: smallValue ? 14 : 18,
                fontWeight: FontWeight.w600,
                color:
                    Theme.of(context).textTheme.bodyLarge?.color ??
                    AppColors.textDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: subtleTextColor)),
            if (barWins != null && barLosses != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: WinRateBar(wins: barWins, losses: barLosses),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecentMatchCard(
    Color cardColor,
    Color subtleTextColor,
    bool isDark,
  ) {
    final m = _recentMatch!;
    final isTeam1 =
        m['player1_id'] == _currentUserId ||
        m['player1_partner_id'] == _currentUserId;
    final iWon = isTeam1
        ? m['winner_id'] == m['player1_id']
        : m['winner_id'] == m['player2_id'];

    double? ratingChange;
    if (m['player1_id'] == _currentUserId) {
      ratingChange = _toDouble(m['player1_rating_change']);
    } else if (m['player2_id'] == _currentUserId) {
      ratingChange = _toDouble(m['player2_rating_change']);
    } else if (m['player1_partner_id'] == _currentUserId) {
      ratingChange = _toDouble(m['player1_partner_rating_change']);
    } else if (m['player2_partner_id'] == _currentUserId) {
      ratingChange = _toDouble(m['player2_partner_rating_change']);
    }
    if (m['is_walkover'] == true) ratingChange = null;
    final isPlayoff = m['match_type'] == 'playoff';

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MatchHistoryScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: (iWon ? AppColors.success : AppColors.danger).withValues(
              alpha: 0.3,
            ),
          ),
          boxShadow: AppShadows.card(isDark),
        ),
        child: Row(
          children: [
            WinLossPill(won: iWon),
            const SizedBox(width: 8),
            sportIcon(m['sport'], size: 18),
            const SizedBox(width: 10),
            if (isPlayoff) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'KNOCKOUT',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: AppColors.accent,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Row(
                children: [
                  Text(
                    'vs ',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color:
                          Theme.of(context).textTheme.bodyLarge?.color ??
                          AppColors.textDark,
                    ),
                  ),
                  Flexible(
                    child: _opponentTeamNameRow(
                      m,
                      _currentUserId,
                      TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color:
                            Theme.of(context).textTheme.bodyLarge?.color ??
                            AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            RatingDeltaText(delta: ratingChange),
          ],
        ),
      ),
    );
  }

  Widget _buildSportSummaryRow(
    String sport,
    Map<String, dynamic> formats,
    Color cardColor,
    Color borderColor,
    bool isDark,
  ) {
    final primaryTextColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark;
    final isTableTennis = sport == 'table_tennis';
    final singles = formats['singles'];
    final doubles = formats['doubles'];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
        boxShadow: AppShadows.card(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              sportIcon(sport, size: 18),
              const SizedBox(width: 10),
              Text(
                _formatSportName(sport),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: primaryTextColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (isTableTennis && singles != null)
            _sportRatingLine('Rating', singles, sport)
          else ...[
            if (singles != null) _sportRatingLine('Singles', singles, sport),
            if (singles != null && doubles != null) const SizedBox(height: 4),
            if (doubles != null) _sportRatingLine('Doubles', doubles, sport),
          ],
        ],
      ),
    );
  }

  Widget _sportRatingLine(String label, Map<String, dynamic> data, String sport) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
            ),
            Text(
              formatRating(sport, data['rating']),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
        if (data['rating'] != null) ...[
          const SizedBox(height: 4),
          RatingScaleBar(sport: sport, rating: data['rating']),
        ],
      ],
    );
  }

  Widget _buildUpcomingMatchRow(
    dynamic m,
    Color cardColor,
    Color borderColor,
    Color subtleTextColor,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LeagueDetailScreen(leagueId: m['league_id']),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
            boxShadow: AppShadows.card(isDark),
          ),
          child: Row(
            children: [
              sportIcon(m['sport'], size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'vs ',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color:
                                Theme.of(context).textTheme.bodyLarge?.color ??
                                AppColors.textDark,
                          ),
                        ),
                        Flexible(
                          child: _opponentTeamNameRow(
                            m,
                            _currentUserId,
                            TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color:
                                  Theme.of(context).textTheme.bodyLarge?.color ??
                                  AppColors.textDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      m['league_name'] ?? m['area'],
                      style: TextStyle(fontSize: 11, color: subtleTextColor),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: subtleTextColor),
            ],
          ),
        ),
      ),
    );
  }
}
