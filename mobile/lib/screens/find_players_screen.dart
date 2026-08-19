// find_players_screen.dart
// Player discovery outside a shared league — GAP-04 from the codebase audit.
// Modeled directly on add_players_screen.dart's search UI (debounce,
// loading/error/empty states), but this isn't scoped to any league and
// tapping a result opens their profile instead of adding them anywhere.
// Safe to be unscoped: PlayerProfileScreen's own backend calls already have
// no shared-league check, so this doesn't expose anything new — it's just a
// front door to data any authenticated user could already reach by id.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../api_client.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/friendly_empty_state.dart';
import '../widgets/friendly_challenge_dialog.dart';
import '../constants/cities.dart';
import '../constants/areas.dart';
import 'player_profile_screen.dart';

const List<String> _findPlayersSports = [
  'badminton',
  'tennis',
  'table_tennis',
  'pickleball',
];

class FindPlayersScreen extends StatefulWidget {
  const FindPlayersScreen({super.key});

  @override
  State<FindPlayersScreen> createState() => _FindPlayersScreenState();
}

class _FindPlayersScreenState extends State<FindPlayersScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _results = [];
  bool _searching = false;
  String? _error;
  Timer? _debounce;

  // 'name' = the original username search; 'rating' = the new similar-rating
  // discovery mode backing friendly-match challenges.
  String _mode = 'name';
  String? _ratingSport;
  List<dynamic> _nearbyResults = [];
  bool _nearbyLoading = false;
  String? _nearbyError;

  // City/area filters for "Similar rating" — pre-seeded from the player's
  // own city (same SharedPreferences read browse_leagues_screen.dart uses)
  // but freely changeable, since the whole point is finding someone at your
  // level in a city you're just visiting, not only your home city.
  String? _nearbyCity;
  String? _nearbyArea;

  @override
  void initState() {
    super.initState();
    _loadMyCity();
  }

  Future<void> _loadMyCity() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    if (userJson != null && mounted) {
      setState(() => _nearbyCity = jsonDecode(userJson)['city']);
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 2) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get(
        '/sports/search',
        queryParams: {'q': query.trim()},
      );

      if (res.statusCode == 200) {
        setState(() => _results = res.data['users']);
      } else {
        setState(() {
          _results = [];
          _error = res.errorOr('Could not search for players.');
        });
      }
    } catch (err) {
      setState(() {
        _results = [];
        _error = 'Could not reach the server.';
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _loadNearby(String sport) async {
    setState(() {
      _ratingSport = sport;
      _nearbyLoading = true;
      _nearbyError = null;
    });
    try {
      final res = await ApiClient.get(
        '/friendlies/nearby',
        queryParams: {
          'sport': sport,
          if (_nearbyCity != null) 'city': _nearbyCity!,
          if (_nearbyArea != null) 'area': _nearbyArea!,
        },
      );
      if (res.statusCode == 200) {
        setState(() => _nearbyResults = res.data['players']);
      } else {
        setState(() {
          _nearbyResults = [];
          _nearbyError = res.errorOr('Could not find nearby players.');
        });
      }
    } catch (err) {
      setState(() {
        _nearbyResults = [];
        _nearbyError = 'Could not reach the server.';
      });
    } finally {
      if (mounted) setState(() => _nearbyLoading = false);
    }
  }

  Future<void> _sendChallenge(dynamic player) async {
    final sport = _ratingSport;
    if (sport == null) return;

    final result = await showFriendlyChallengeDialog(
      context,
      opponentName: player['username'],
      sportOptions: [sport],
      presetSport: sport,
    );
    if (result == null || !mounted) return;

    HapticFeedback.lightImpact();
    try {
      final res = await ApiClient.post(
        '/friendlies/challenge',
        body: {
          'opponentId': player['id'],
          'sport': result['sport'],
          'proposedTime': result['proposedTime'],
          'venue': result['venue'],
        },
      );
      if (!mounted) return;
      if (res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Challenge sent to ${player['username']}!'),
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

  String _formatSport(String sport) => sport
      .split('_')
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final borderColor = AppColors.cardBorder(isDark);
    final titleColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark;
    final subtitleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade700;

    return Scaffold(
      appBar: AppBar(title: const Text('Find Players')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: _ModeChip(
                    label: 'Search by name',
                    selected: _mode == 'name',
                    onTap: () => setState(() => _mode = 'name'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ModeChip(
                    label: 'Similar rating',
                    selected: _mode == 'rating',
                    onTap: () => setState(() => _mode = 'rating'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _mode == 'name'
                ? _buildNameSearch(
                    cardColor,
                    borderColor,
                    titleColor,
                    subtitleColor,
                    isDark,
                  )
                : _buildRatingSearch(
                    cardColor,
                    borderColor,
                    titleColor,
                    subtitleColor,
                    isDark,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameSearch(
    Color cardColor,
    Color borderColor,
    Color titleColor,
    Color subtitleColor,
    bool isDark,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: const InputDecoration(
              labelText: 'Search by username',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        Expanded(
          child: _searching
              ? const SkeletonList(count: 3)
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
                          onPressed: () => _search(_searchController.text),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _results.isEmpty
              ? FriendlyEmptyState(
                  icon: Icons.person_search,
                  title: _searchController.text.trim().length < 2
                      ? 'Type at least 2 characters to search.'
                      : 'No matching players found.',
                )
              : RefreshIndicator(
                  onRefresh: () => _search(_searchController.text),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final user = _results[index];

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderColor),
                          boxShadow: AppShadows.card(isDark),
                        ),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    PlayerProfileScreen(userId: user['id']),
                              ),
                            );
                          },
                          title: Text(
                            user['username'],
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: titleColor,
                            ),
                          ),
                          subtitle: Text(
                            user['location'] ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              color: subtitleColor,
                            ),
                          ),
                          trailing: user['rating'] != null
                              ? Text(
                                  '${user['rating']}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.accent,
                                  ),
                                )
                              : Icon(
                                  Icons.chevron_right,
                                  color: subtitleColor,
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

  Widget _buildRatingSearch(
    Color cardColor,
    Color borderColor,
    Color titleColor,
    Color subtitleColor,
    bool isDark,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _nearbyCity,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'City',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Any')),
                    ...indianCities.map(
                      (c) => DropdownMenuItem(value: c, child: Text(c)),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _nearbyCity = v;
                      // An area picked under a different city no longer applies.
                      _nearbyArea = null;
                    });
                    if (_ratingSport != null) _loadNearby(_ratingSport!);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _nearbyArea,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Area',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Any')),
                    ...(areasByCity[_nearbyCity] ?? []).map(
                      (a) => DropdownMenuItem(value: a, child: Text(a)),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() => _nearbyArea = v);
                    if (_ratingSport != null) _loadNearby(_ratingSport!);
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Wrap(
            spacing: 8,
            children: _findPlayersSports.map((sport) {
              return ChoiceChip(
                label: Text(_formatSport(sport)),
                selected: _ratingSport == sport,
                onSelected: (_) => _loadNearby(sport),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: _ratingSport == null
              ? FriendlyEmptyState(
                  icon: Icons.leaderboard_outlined,
                  title: 'Pick a sport',
                  subtitle: 'See players closest to your rating.',
                )
              : _nearbyLoading
              ? const SkeletonList(count: 3)
              : _nearbyError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_nearbyError!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => _loadNearby(_ratingSport!),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _nearbyResults.isEmpty
              ? FriendlyEmptyState(
                  icon: Icons.leaderboard_outlined,
                  title: 'No other players found for this sport yet.',
                )
              : RefreshIndicator(
                  onRefresh: () => _loadNearby(_ratingSport!),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _nearbyResults.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final player = _nearbyResults[index];

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderColor),
                          boxShadow: AppShadows.card(isDark),
                        ),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PlayerProfileScreen(
                                  userId: player['id'],
                                ),
                              ),
                            );
                          },
                          title: Text(
                            player['username'],
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: titleColor,
                            ),
                          ),
                          subtitle: Text(
                            player['location'] ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              color: subtitleColor,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (player['rating'] != null)
                                Text(
                                  '${player['rating']}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.accent,
                                  ),
                                ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.sports_tennis, size: 20),
                                tooltip: 'Challenge to a friendly match',
                                onPressed: () => _sendChallenge(player),
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
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label, textAlign: TextAlign.center),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}
