// browse_leagues_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import 'create_league_screen.dart';
import 'league_detail_screen.dart';

const String apiUrl = 'http://localhost:3000/api';

class BrowseLeaguesScreen extends StatefulWidget {
  const BrowseLeaguesScreen({super.key});

  @override
  State<BrowseLeaguesScreen> createState() => _BrowseLeaguesScreenState();
}

class _BrowseLeaguesScreenState extends State<BrowseLeaguesScreen> {
  List<dynamic> _leagues = [];
  bool _loading = true;
  bool _didJoinAny = false;

  @override
  void initState() {
    super.initState();
    _loadLeagues();
  }

  Future<void> _loadLeagues() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.get(
        Uri.parse('$apiUrl/leagues'),
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

  Future<void> _joinLeague(int leagueId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.post(
        Uri.parse('$apiUrl/leagues/$leagueId/join'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;
      if (response.statusCode == 201) {
        _didJoinAny = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Joined league!'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadLeagues();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not join.'),
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {},
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Browse Leagues'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _didJoinAny),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadLeagues,
                child: _leagues.isEmpty
                    ? ListView(
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5,
                            child: Center(
                              child: Text(
                                'No leagues yet.\nBe the first to create one!',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
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
                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => LeagueDetailScreen(
                                      leagueId: league['id'],
                                    ),
                                  ),
                                );
                                if (result == 'deleted') _loadLeagues();
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${_formatSport(league['sport'])} · ${league['area']}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            '${league['season_start']} – ${league['season_end']}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textGrey,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Wrap(
                                            spacing: 5,
                                            children: [
                                              _tag(league['format']),
                                              _tag(
                                                league['gender_category'] ==
                                                        'mens'
                                                    ? "Men's"
                                                    : "Women's",
                                              ),
                                              _tag(
                                                '${league['member_count']} players',
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 9,
                                        ),
                                      ),
                                      onPressed: () =>
                                          _joinLeague(league['id']),
                                      child: const Text(
                                        'Join',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final created = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CreateLeagueScreen(),
              ),
            );
            if (created == true) _loadLeagues();
          },
          icon: const Icon(Icons.add),
          label: const Text('Create'),
        ),
      ),
    );
  }

  Widget _tag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: AppColors.textGrey),
      ),
    );
  }
}
