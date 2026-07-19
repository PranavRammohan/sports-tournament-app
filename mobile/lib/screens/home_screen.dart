// home_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../config.dart';
import '../widgets/sport_icon.dart';
import 'my_leagues_screen.dart';
import 'match_history_screen.dart';
import 'pending_matches_screen.dart';
import 'league_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _username = '';
  int _leagueCount = 0;
  int _matchesPlayed = 0;
  int _wins = 0;
  List<dynamic> _sports = [];
  List<dynamic> _pendingMatches = [];
  List<dynamic> _upcomingMatches = [];
  Map<String, dynamic>? _recentMatch;
  int? _currentUserId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEverything();
  }

  Future<void> _loadEverything() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final userJson = prefs.getString('user');
      if (userJson != null) {
        final userData = jsonDecode(userJson);
        _username = userData['username'] ?? '';
        _currentUserId = userData['id'];
      }

      final leaguesRes = await http.get(
        Uri.parse('$baseApiUrl/leagues/mine'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final leaguesData = jsonDecode(leaguesRes.body);
      if (leaguesRes.statusCode == 200) {
        _leagueCount = (leaguesData['leagues'] as List).length;
      }

      final sportsRes = await http.get(
        Uri.parse('$baseApiUrl/sports/mine'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final sportsData = jsonDecode(sportsRes.body);
      if (sportsRes.statusCode == 200) {
        final Map<String, dynamic> seenSports = {};
        for (final row in sportsData['sports']) {
          seenSports[row['sport']] = row;
        }
        _sports = seenSports.values.toList();
        _matchesPlayed = _sports.fold<int>(
          0,
          (sum, r) => sum + (r['matches_played'] as int),
        );
        _wins = _sports.fold<int>(0, (sum, r) => sum + (r['wins'] as int));
      }

      final pendingRes = await http.get(
        Uri.parse('$baseApiUrl/matches/pending'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final pendingData = jsonDecode(pendingRes.body);
      if (pendingRes.statusCode == 200) {
        _pendingMatches = pendingData['matches'];
      }

      final upcomingRes = await http.get(
        Uri.parse('$baseApiUrl/matches/upcoming'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final upcomingData = jsonDecode(upcomingRes.body);
      if (upcomingRes.statusCode == 200) {
        _upcomingMatches = upcomingData['upcoming'];
      }

      final historyRes = await http.get(
        Uri.parse('$baseApiUrl/matches/history'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final historyData = jsonDecode(historyRes.body);
      if (historyRes.statusCode == 200 &&
          (historyData['matches'] as List).isNotEmpty) {
        _recentMatch = historyData['matches'][0];
      }
    } catch (err) {
      // fail silently, pull-to-refresh available
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

  String _opponentLabel(dynamic m, int? currentUserId) {
    final isTeam1 =
        m['player1_id'] == currentUserId ||
        m['player1_partner_id'] == currentUserId;
    final isDoubles = m['player1_partner_username'] != null;
    if (isTeam1) {
      return isDoubles
          ? '${m['player2_username']} & ${m['player2_partner_username']}'
          : m['player2_username'];
    } else {
      return isDoubles
          ? '${m['player1_username']} & ${m['player1_partner_username']}'
          : m['player1_username'];
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
    final winRate = _matchesPlayed == 0
        ? 0
        : ((_wins / _matchesPlayed) * 100).round();
    final losses = _matchesPlayed - _wins;

    return Scaffold(
      appBar: AppBar(title: const Text('RallyX')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadEverything,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Welcome header with gradient
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: Colors.white,
                          child: Text(
                            _username.isNotEmpty
                                ? _username[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
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

                  // Stat cards
                  Row(
                    children: [
                      Expanded(
                        child: _statCard(
                          Icons.list_alt,
                          'Leagues',
                          '$_leagueCount',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MyLeaguesScreen(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statCard(
                          Icons.sports_score,
                          'Matches',
                          '$_matchesPlayed',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MatchHistoryScreen(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statCard(
                          Icons.emoji_events,
                          'Win rate',
                          '$winRate% ($_wins-$losses)',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MatchHistoryScreen(),
                            ),
                          ),
                          smallValue: true,
                        ),
                      ),
                    ],
                  ),

                  // Pending confirmations banner
                  if (_pendingMatches.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PendingMatchesScreen(),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.1),
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: AppColors.textDark,
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

                  // Recent match highlight
                  if (_recentMatch != null) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Last Match',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    _buildRecentMatchCard(),
                  ],

                  // Your Sports summary
                  if (_sports.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Your Sports',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    ..._sports.map((s) => _buildSportSummaryRow(s)),
                  ],

                  // Upcoming matches
                  if (_upcomingMatches.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Upcoming Matches',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    ..._upcomingMatches.map((m) => _buildUpcomingMatchRow(m)),
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
    String value, {
    required VoidCallback onTap,
    bool smallValue = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: smallValue ? 14 : 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentMatchCard() {
    final m = _recentMatch!;
    final isTeam1 =
        m['player1_id'] == _currentUserId ||
        m['player1_partner_id'] == _currentUserId;
    final iWon = isTeam1
        ? m['winner_id'] == m['player1_id']
        : m['winner_id'] == m['player2_id'];
    final opponent = _opponentLabel(m, _currentUserId);

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
    final changeText = ratingChange == null
        ? ''
        : (ratingChange >= 0
              ? '+${ratingChange.toStringAsFixed(2)}'
              : ratingChange.toStringAsFixed(2));

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MatchHistoryScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: (iWon ? AppColors.success : AppColors.danger).withValues(
              alpha: 0.3,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: iWon ? AppColors.success : AppColors.danger,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                iWon ? 'WIN' : 'LOSS',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            sportIcon(m['sport'], size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'vs $opponent',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (ratingChange != null)
              Text(
                changeText,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: ratingChange >= 0
                      ? AppColors.success
                      : AppColors.danger,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSportSummaryRow(dynamic s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          sportIcon(s['sport'], size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _formatSportName(s['sport']),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Text(
            '${s['rating']}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingMatchRow(dynamic m) {
    final isTeam1 =
        m['player1_id'] == _currentUserId ||
        m['player1_partner_id'] == _currentUserId;
    final isDoubles = m['player1_partner_username'] != null;
    final opponent = isTeam1
        ? (isDoubles
              ? '${m['player2_username']} & ${m['player2_partner_username']}'
              : m['player2_username'])
        : (isDoubles
              ? '${m['player1_username']} & ${m['player1_partner_username']}'
              : m['player1_username']);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LeagueDetailScreen(leagueId: m['league_id']),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              sportIcon(m['sport'], size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'vs $opponent',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      m['area'],
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
