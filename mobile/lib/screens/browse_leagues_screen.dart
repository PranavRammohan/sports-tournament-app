// browse_leagues_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../config.dart';
import '../utils.dart';
import '../widgets/sport_icon.dart';
import 'create_league_screen.dart';
import 'league_detail_screen.dart';

class BrowseLeaguesScreen extends StatefulWidget {
  const BrowseLeaguesScreen({super.key});

  @override
  State<BrowseLeaguesScreen> createState() => _BrowseLeaguesScreenState();
}

class _BrowseLeaguesScreenState extends State<BrowseLeaguesScreen> {
  List<dynamic> _leagues = [];
  bool _loading = true;
  bool _didJoinAny = false;

  String? _filterFormat;

  final TextEditingController _codeController = TextEditingController();
  bool _joiningByCode = false;

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

      final queryParams = <String, String>{};
      if (_filterFormat != null) queryParams['format'] = _filterFormat!;

      final uri = Uri.parse(
        '$baseApiUrl/leagues',
      ).replace(queryParameters: queryParams.isEmpty ? null : queryParams);

      final response = await http.get(
        uri,
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
        Uri.parse('$baseApiUrl/leagues/$leagueId/join'),
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

  Future<void> _joinByCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a join code.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _joiningByCode = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.post(
        Uri.parse('$baseApiUrl/leagues/join-by-code'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'code': code}),
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;
      if (response.statusCode != 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not join.'),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }

      _didJoinAny = true;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LeagueDetailScreen(leagueId: data['leagueId']),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Network error.')));
    } finally {
      if (mounted) setState(() => _joiningByCode = false);
    }
  }

  String _formatSport(String sport) => sport
      .split('_')
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final borderColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    final subtleTextColor = isDark
        ? Colors.grey.shade400
        : Colors.grey.shade600;
    final primaryTextColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {},
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Browse Leagues'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context, _didJoinAny),
            ),
            bottom: const TabBar(
              indicatorColor: AppColors.accent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: [
                Tab(text: 'Public'),
                Tab(text: 'Private'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _buildPublicTab(
                cardColor,
                borderColor,
                subtleTextColor,
                primaryTextColor,
              ),
              _buildPrivateTab(),
            ],
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
      ),
    );
  }

  Widget _buildPublicTab(
    Color cardColor,
    Color borderColor,
    Color subtleTextColor,
    Color primaryTextColor,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: DropdownButtonFormField<String>(
            initialValue: _filterFormat,
            decoration: const InputDecoration(
              labelText: 'Format',
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('Any')),
              DropdownMenuItem(value: 'singles', child: Text('Singles')),
              DropdownMenuItem(value: 'doubles', child: Text('Doubles')),
            ],
            onChanged: (v) {
              setState(() => _filterFormat = v);
              _loadLeagues();
            },
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadLeagues,
                  child: _leagues.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.4,
                              child: Center(
                                child: Text(
                                  'No leagues match these filters.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: subtleTextColor),
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _leagues.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final league = _leagues[index];
                            return Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: borderColor),
                              ),
                              child: Material(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(8),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () async {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            LeagueDetailScreen(
                                              leagueId: league['id'],
                                            ),
                                      ),
                                    );
                                    if (result == 'deleted' ||
                                        result == 'left' ||
                                        result == 'joined') {
                                      _didJoinAny =
                                          _didJoinAny || result == 'joined';
                                      _loadLeagues();
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        sportIcon(league['sport'], size: 22),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                league['name'],
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                  color: primaryTextColor,
                                                ),
                                              ),
                                              const SizedBox(height: 1),
                                              Text(
                                                '${_formatSport(league['sport'])} · ${league['area']}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: subtleTextColor,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                '${formatDateOnly(league['season_start'])} – ${formatDateOnly(league['season_end'])} · ${league['member_count']} players',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: subtleTextColor,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Wrap(
                                                spacing: 5,
                                                children: [
                                                  _tag(
                                                    league['format'],
                                                    subtleTextColor,
                                                  ),
                                                  _tag(
                                                    league['gender_category'] ==
                                                            'mens'
                                                        ? "Men's"
                                                        : "Women's",
                                                    subtleTextColor,
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          Icons.chevron_right,
                                          color: subtleTextColor,
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
    );
  }

  Widget _buildPrivateTab() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 44, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Private leagues are invite-only.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Enter the join code shared by the host to join one.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _codeController,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Join Code',
                prefixIcon: Icon(Icons.key_outlined),
              ),
              style: const TextStyle(fontSize: 18, letterSpacing: 3),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _joiningByCode ? null : _joinByCode,
              child: _joiningByCode
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text('Join League'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String text, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: textColor)),
    );
  }
}
