// player_profile_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../config.dart';
import '../widgets/sport_icon.dart';

class PlayerProfileScreen extends StatefulWidget {
  final int userId;

  const PlayerProfileScreen({super.key, required this.userId});

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  Map<String, dynamic>? _user;
  List<dynamic> _sports = [];
  bool _loading = true;
  String? _error;

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
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.get(
        Uri.parse('$baseApiUrl/sports/user/${widget.userId}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);

      if (response.statusCode != 200) {
        setState(
          () => _error = data['error'] ?? 'Could not load this profile.',
        );
        return;
      }

      setState(() {
        _user = data['user'];
        _sports = data['sports'];
      });
    } catch (err) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      setState(() => _loading = false);
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
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
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
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  backgroundImage: hasProfilePic
                      ? NetworkImage(profilePicUrl)
                      : null,
                  child: !hasProfilePic
                      ? Text(
                          (_user?['username'] ?? '?')[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        )
                      : null,
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
            ],
          ),
          Text(
            '${data['rating']}',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}
