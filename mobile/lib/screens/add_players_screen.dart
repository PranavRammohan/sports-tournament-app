// add_players_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../config.dart';

class AddPlayersScreen extends StatefulWidget {
  final int leagueId;

  const AddPlayersScreen({super.key, required this.leagueId});

  @override
  State<AddPlayersScreen> createState() => _AddPlayersScreenState();
}

class _AddPlayersScreenState extends State<AddPlayersScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _results = [];
  bool _searching = false;
  Timer? _debounce;
  final Set<int> _addingIds = {};
  final Set<int> _addedIds = {};

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 2) {
      setState(() => _results = []);
      return;
    }

    setState(() => _searching = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final uri = Uri.parse(
        '$baseApiUrl/leagues/${widget.leagueId}/search-players',
      ).replace(queryParameters: {'q': query.trim()});

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        setState(() => _results = data['users']);
      } else {
        setState(() => _results = []);
      }
    } catch (err) {
      setState(() => _results = []);
    } finally {
      setState(() => _searching = false);
    }
  }

  Future<void> _addPlayer(int playerId) async {
    setState(() => _addingIds.add(playerId));

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.post(
        Uri.parse('$baseApiUrl/leagues/${widget.leagueId}/add-player'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'playerId': playerId}),
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;
      if (response.statusCode == 201) {
        setState(() => _addedIds.add(playerId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Player added!'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not add player.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Network error.')));
    } finally {
      if (mounted) setState(() => _addingIds.remove(playerId));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _handleBack() {
    Navigator.pop(context, _addedIds.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final borderColor = isDark ? Colors.grey.shade700 : Colors.grey.shade200;
    final titleColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark;
    final subtitleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade700;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Add Players'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBack,
          ),
        ),
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
                  ? const Center(child: CircularProgressIndicator())
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
                        final isAdding = _addingIds.contains(user['id']);
                        final isAdded = _addedIds.contains(user['id']);

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: borderColor),
                          ),
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
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
                            trailing: isAdded
                                ? const Icon(
                                    Icons.check_circle,
                                    color: AppColors.success,
                                  )
                                : ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                    ),
                                    onPressed: isAdding
                                        ? null
                                        : () => _addPlayer(user['id']),
                                    child: isAdding
                                        ? const SizedBox(
                                            height: 14,
                                            width: 14,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text(
                                            'Add',
                                            style: TextStyle(fontSize: 13),
                                          ),
                                  ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
