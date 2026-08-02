// find_players_screen.dart
// Player discovery outside a shared league — GAP-04 from the codebase audit.
// Modeled directly on add_players_screen.dart's search UI (debounce,
// loading/error/empty states), but this isn't scoped to any league and
// tapping a result opens their profile instead of adding them anywhere.
// Safe to be unscoped: PlayerProfileScreen's own backend calls already have
// no shared-league check, so this doesn't expose anything new — it's just a
// front door to data any authenticated user could already reach by id.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../api_client.dart';
import '../widgets/loading_skeleton.dart';
import 'player_profile_screen.dart';

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
            padding: const EdgeInsets.all(16),
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
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _searchController.text.trim().length < 2
                            ? 'Type at least 2 characters to search.'
                            : 'No matching players found.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  )
                : ListView.separated(
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
        ],
      ),
    );
  }
}
