// notifications_screen.dart
// In-app notification log — GAP-01 phase one from the codebase audit. Modeled
// directly on pending_matches_screen.dart's shape (loading/error/empty/list
// states, RefreshIndicator, fade-in item animation). Not push/FCM — just a
// list backed by the backend's notifications table, populated at the events
// that matter (partner requests, match confirm/reject, being added to a
// tournament) via notifications.js's createNotification/createNotifications.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../api_client.dart';
import '../date_utils.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/friendly_empty_state.dart';
import 'league_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<dynamic> _notifications = [];
  bool _loading = true;
  String? _error;
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void refresh() {
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get('/notifications');
      if (res.statusCode == 200) {
        setState(() => _notifications = res.data['notifications']);
      } else {
        setState(() => _error = res.errorOr('Could not load notifications.'));
      }
    } catch (err) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    if (_markingAll) return;
    HapticFeedback.lightImpact();
    setState(() => _markingAll = true);
    try {
      final res = await ApiClient.patch('/notifications/read-all');
      if (res.statusCode == 200) {
        setState(() {
          for (final n in _notifications) {
            n['read'] = true;
          }
        });
      }
    } catch (err) {
      // fail silently — worst case the list still shows unread until retried
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _onTapNotification(dynamic n) async {
    if (n['read'] != true) {
      setState(() => n['read'] = true);
      try {
        await ApiClient.patch('/notifications/${n['id']}/read');
      } catch (err) {
        // fail silently — a missed read-receipt isn't worth surfacing an error for
      }
    }
    if (!mounted) return;
    if (n['league_id'] != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LeagueDetailScreen(leagueId: n['league_id']),
        ),
      );
    }
  }

  bool get _hasUnread => _notifications.any((n) => n['read'] != true);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final subtleTextColor = isDark
        ? Colors.grey.shade400
        : Colors.grey.shade700;
    final primaryTextColor = isDark ? Colors.white : AppColors.textDark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_hasUnread)
            TextButton(
              onPressed: _markingAll ? null : _markAllRead,
              child: _markingAll
                  ? const SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Mark all read'),
            ),
        ],
      ),
      body: _loading
          ? const SkeletonList()
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
          : RefreshIndicator(
              onRefresh: _load,
              child: _notifications.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.5,
                          child: const FriendlyEmptyState(
                            icon: Icons.notifications_none,
                            title: 'Nothing here yet.',
                            subtitle:
                                "You'll see partner requests and match updates here.",
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _notifications.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final n = _notifications[index];
                        final isUnread = n['read'] != true;

                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: Duration(
                            milliseconds: 180 + (index * 30).clamp(0, 400),
                          ),
                          builder: (context, value, child) =>
                              Opacity(opacity: value, child: child),
                          child: MergeSemantics(
                            child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _onTapNotification(n),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isUnread
                                      ? AppColors.accent.withValues(alpha: 0.4)
                                      : AppColors.cardBorder(isDark),
                                ),
                                boxShadow: AppShadows.card(isDark),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (isUnread)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 5,
                                        right: 8,
                                      ),
                                      child: Semantics(
                                        label: 'Unread',
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: AppColors.accent,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          n['title'] ?? '',
                                          style: TextStyle(
                                            fontWeight: isUnread
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            fontSize: 13,
                                            color: primaryTextColor,
                                          ),
                                        ),
                                        if (n['body'] != null) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            n['body'],
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: subtleTextColor,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 4),
                                        Text(
                                          formatRelativeTime(n['created_at']),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: subtleTextColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (n['league_id'] != null)
                                    Icon(
                                      Icons.chevron_right,
                                      size: 18,
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
    );
  }
}
