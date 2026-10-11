// blocked_players_screen.dart
// Lists players the current user has blocked (see player_profile_screen.
// dart's Block action) with an unblock button each. Reachable from Profile
// settings, same placement pattern as the Privacy Policy link.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../api_client.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/friendly_empty_state.dart';

class BlockedPlayersScreen extends StatefulWidget {
  const BlockedPlayersScreen({super.key});

  @override
  State<BlockedPlayersScreen> createState() => _BlockedPlayersScreenState();
}

class _BlockedPlayersScreenState extends State<BlockedPlayersScreen> {
  List<dynamic> _blocked = [];
  bool _loading = true;
  String? _error;
  final Set<dynamic> _actingIds = {};

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
      final res = await ApiClient.get('/blocks');
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() => _blocked = res.data['blocked']);
      } else {
        setState(() => _error = res.errorOr('Could not load blocked players.'));
      }
    } catch (err) {
      if (mounted) setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unblock(dynamic user) async {
    setState(() => _actingIds.add(user['id']));
    try {
      final res = await ApiClient.delete('/blocks/${user['id']}');
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() => _blocked.removeWhere((b) => b['id'] == user['id']));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user['username']} unblocked.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errorOr('Could not unblock this player.')),
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
      if (mounted) setState(() => _actingIds.remove(user['id']));
    }
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
      appBar: AppBar(title: const Text('Blocked Players')),
      body: _loading
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
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          : _blocked.isEmpty
          ? FriendlyEmptyState(
              icon: Icons.block_outlined,
              title: "You haven't blocked anyone.",
              subtitle: 'Players you block from their profile will show up here.',
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _blocked.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final user = _blocked[index];
                  final isActing = _actingIds.contains(user['id']);

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderColor),
                      boxShadow: AppShadows.card(isDark),
                    ),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        user['username'] ?? '',
                        style: TextStyle(fontWeight: FontWeight.w600, color: titleColor),
                      ),
                      subtitle: Text(
                        user['location'] ?? '',
                        style: TextStyle(fontSize: 12, color: subtitleColor),
                      ),
                      trailing: TextButton(
                        onPressed: isActing
                            ? null
                            : () {
                                HapticFeedback.selectionClick();
                                _unblock(user);
                              },
                        child: isActing
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Unblock'),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
