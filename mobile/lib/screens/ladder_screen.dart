// ladder_screen.dart
// Standalone ladder mode — a persistent, always-on ranked list per
// sport+city, separate from the sport rating shown everywhere else (see
// backend/migration_ladder.sql's header for why). Embedded as a mode inside
// find_players_screen.dart (no Scaffold/AppBar of its own), same pattern
// as that screen's existing "Search by name"/"Similar rating" modes.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../api_client.dart';
import '../constants/cities.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/friendly_empty_state.dart';
import '../widgets/friendly_challenge_dialog.dart';

const List<String> _ladderSports = [
  'badminton',
  'tennis',
  'table_tennis',
  'pickleball',
];

// Must match CHALLENGE_RANGE in backend/ladderRoutes.js.
const int _challengeRange = 5;

class LadderView extends StatefulWidget {
  const LadderView({super.key});

  @override
  State<LadderView> createState() => _LadderViewState();
}

class _LadderViewState extends State<LadderView> {
  int? _currentUserId;
  String? _selectedSport;
  String? _selectedCity;
  List<dynamic> _members = [];
  bool _loading = false;
  bool _acting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMyInfo();
  }

  Future<void> _loadMyInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    if (!mounted) return;
    if (userJson != null) {
      final user = jsonDecode(userJson);
      setState(() {
        _currentUserId = user['id'];
        _selectedCity = user['city'];
      });
    }
  }

  Future<void> _loadLadder(String sport) async {
    if (_selectedCity == null) return;
    setState(() {
      _selectedSport = sport;
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get(
        '/ladder/$sport',
        queryParams: {'city': _selectedCity!},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() => _members = res.data['members']);
      } else {
        setState(() {
          _members = [];
          _error = res.errorOr('Could not load the ladder.');
        });
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          _members = [];
          _error = 'Could not reach the server.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _amIMember =>
      _members.any((m) => m['user_id'] == _currentUserId);

  int? get _myPosition {
    for (final m in _members) {
      if (m['user_id'] == _currentUserId) return m['position'] as int;
    }
    return null;
  }

  Future<void> _join() async {
    if (_selectedSport == null || _selectedCity == null) return;
    HapticFeedback.lightImpact();
    setState(() => _acting = true);
    try {
      final res = await ApiClient.post(
        '/ladder/join',
        body: {'sport': _selectedSport, 'city': _selectedCity},
      );
      if (!mounted) return;
      if (res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Joined the ladder!'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadLadder(_selectedSport!);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not join the ladder.')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Network error.')));
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Text('Leave this ladder?'),
        content: const Text(
          'You\'ll lose your position and anyone below you moves up. You can always rejoin later, at the bottom.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (_selectedSport == null || _selectedCity == null) return;

    HapticFeedback.mediumImpact();
    setState(() => _acting = true);
    try {
      final res = await ApiClient.delete(
        '/ladder/leave',
        body: {'sport': _selectedSport, 'city': _selectedCity},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        _loadLadder(_selectedSport!);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not leave the ladder.')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Network error.')));
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _challenge(dynamic member) async {
    final result = await showFriendlyChallengeDialog(
      context,
      opponentName: member['username'],
      sportOptions: [_selectedSport!],
      presetSport: _selectedSport,
      description:
          'A ladder challenge moves your position if you win — it never affects your sport rating.',
    );
    if (result == null || !mounted) return;

    HapticFeedback.lightImpact();
    try {
      final res = await ApiClient.post(
        '/ladder/challenge',
        body: {
          'sport': _selectedSport,
          'city': _selectedCity,
          'defenderId': member['user_id'],
          'proposedTime': result['proposedTime'],
          'venue': result['venue'],
        },
      );
      if (!mounted) return;
      if (res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Challenge sent to ${member['username']}!'),
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

  // Null means eligible; non-null is the reason a Challenge button is
  // disabled for this row.
  String? _ineligibleReason(dynamic member) {
    final myPosition = _myPosition;
    if (myPosition == null) return "Join the ladder to challenge";
    if (member['user_id'] == _currentUserId) return null; // caller skips self rows entirely
    final theirPosition = member['position'] as int;
    if (theirPosition >= myPosition) return "Only players above you";
    if (myPosition - theirPosition > _challengeRange) {
      return "Too far above you (max $_challengeRange spots)";
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final borderColor = AppColors.cardBorder(isDark);
    final titleColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark;
    final subtitleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade700;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: DropdownButtonFormField<String>(
            initialValue: _selectedCity,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'City', isDense: true),
            items: indianCities
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) {
              setState(() => _selectedCity = v);
              if (_selectedSport != null) _loadLadder(_selectedSport!);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Wrap(
            spacing: 8,
            children: _ladderSports.map((sport) {
              return ChoiceChip(
                label: Text(_formatSport(sport)),
                selected: _selectedSport == sport,
                onSelected: (_) => _loadLadder(sport),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: _selectedSport == null
              ? FriendlyEmptyState(
                  icon: Icons.format_list_numbered,
                  title: 'Pick a sport',
                  subtitle: 'See the ladder for this city and sport.',
                )
              : _loading
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
                          onPressed: () => _loadLadder(_selectedSport!),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _amIMember
                                  ? 'Your position: #$_myPosition'
                                  : "You're not on this ladder yet.",
                              style: TextStyle(fontSize: 12, color: subtitleColor),
                            ),
                          ),
                          if (_acting)
                            const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else if (_amIMember)
                            TextButton(onPressed: _leave, child: const Text('Leave'))
                          else
                            ElevatedButton(onPressed: _join, child: const Text('Join')),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _members.isEmpty
                          ? FriendlyEmptyState(
                              icon: Icons.format_list_numbered,
                              title: 'No one on this ladder yet.',
                              subtitle: 'Be the first to join.',
                            )
                          : RefreshIndicator(
                              onRefresh: () => _loadLadder(_selectedSport!),
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: _members.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final member = _members[index];
                                  final isMe = member['user_id'] == _currentUserId;
                                  final reason = isMe ? null : _ineligibleReason(member);

                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isMe
                                          ? AppColors.accent.withValues(alpha: 0.08)
                                          : cardColor,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isMe ? AppColors.accent : borderColor,
                                      ),
                                      boxShadow: AppShadows.card(isDark),
                                    ),
                                    child: ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: CircleAvatar(
                                        radius: 16,
                                        child: Text('${member['position']}'),
                                      ),
                                      title: Text(
                                        isMe ? '${member['username']} (you)' : member['username'],
                                        style: TextStyle(fontWeight: FontWeight.w600, color: titleColor),
                                      ),
                                      subtitle: member['rating'] != null
                                          ? Text(
                                              'Rating ${member['rating']}',
                                              style: TextStyle(fontSize: 12, color: subtitleColor),
                                            )
                                          : null,
                                      trailing: isMe
                                          ? null
                                          : Tooltip(
                                              message: reason ?? 'Send a challenge',
                                              child: IconButton(
                                                icon: const Icon(Icons.sports_tennis, size: 20),
                                                onPressed: reason != null
                                                    ? null
                                                    : () => _challenge(member),
                                              ),
                                            ),
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
