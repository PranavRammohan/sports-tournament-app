// my_leagues_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../config.dart';
import '../utils.dart';
import '../widgets/sport_icon.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/friendly_empty_state.dart';
import 'league_detail_screen.dart';
import 'browse_leagues_screen.dart';
import 'join_by_code_screen.dart';

class MyLeaguesScreen extends StatefulWidget {
  const MyLeaguesScreen({super.key});

  @override
  State<MyLeaguesScreen> createState() => _MyLeaguesScreenState();
}

class _MyLeaguesScreenState extends State<MyLeaguesScreen> {
  List<dynamic> _leagues = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLeagues();
  }

  void refresh() {
    _loadLeagues();
  }

  Future<void> _loadLeagues() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.get(
        Uri.parse('$baseApiUrl/leagues/mine'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        setState(() => _leagues = data['leagues']);
      }
    } catch (err) {
      // fail silently
    } finally {
      setState(() => _loading = false);
    }
  }

  String _formatSport(String sport) => sport
      .split('_')
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tournaments'),
        actions: [
          IconButton(
            icon: const Icon(Icons.key_outlined),
            tooltip: 'Join with code',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const JoinByCodeScreen()),
              );
              if (result != null) _loadLeagues();
            },
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Browse tournaments',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BrowseLeaguesScreen()),
              );
              if (result == true) _loadLeagues();
            },
          ),
        ],
      ),
      body: _loading
          ? const SkeletonList()
          : RefreshIndicator(
              onRefresh: _loadLeagues,
              child: _leagues.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: FriendlyEmptyState(
                            icon: Icons.emoji_events_outlined,
                            title: "You haven't joined any tournaments yet.",
                            subtitle: 'Find one to join, or start your own.',
                            actionLabel: 'Browse tournaments',
                            onAction: () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const BrowseLeaguesScreen(),
                                ),
                              );
                              if (result == true) _loadLeagues();
                            },
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _leagues.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final league = _leagues[index];
                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: Duration(
                            milliseconds: 200 + (index * 40).clamp(0, 400),
                          ),
                          builder: (context, value, child) =>
                              Opacity(opacity: value, child: child),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Material(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(8),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 2,
                                ),
                                leading: sportIcon(league['sport'], size: 22),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        league['name'],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (league['is_private'] == true)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 6),
                                        child: Icon(
                                          Icons.lock_outline,
                                          size: 14,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  '${_formatSport(league['sport'])} · ${league['area']} · ${formatDateOnly(league['season_start'])} – ${formatDateOnly(league['season_end'])} · ${league['member_count']} players',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right,
                                  size: 20,
                                ),
                                onTap: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => LeagueDetailScreen(
                                        leagueId: league['id'],
                                      ),
                                    ),
                                  );
                                  if (result == 'deleted' ||
                                      result == 'left' ||
                                      result == 'joined') {
                                    _loadLeagues();
                                  }
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
