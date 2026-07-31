// my_leagues_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../api_client.dart';
import '../utils.dart';
import '../widgets/sport_icon.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/friendly_empty_state.dart';
import '../widgets/fade_in_list_item.dart';
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLeagues();
  }

  void refresh() {
    _loadLeagues();
  }

  Future<void> _loadLeagues() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get('/leagues/mine');
      if (res.statusCode == 200) {
        setState(() => _leagues = res.data['leagues']);
      } else {
        setState(
          () => _error = res.errorOr('Could not load your tournaments.'),
        );
      }
    } catch (err) {
      setState(() => _error = 'Could not reach the server.');
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tournaments'),
        actions: [
          IconButton(
            icon: const Icon(Icons.key_outlined),
            tooltip: 'Join with code',
            onPressed: () async {
              HapticFeedback.selectionClick();
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
              HapticFeedback.selectionClick();
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
                      onPressed: _loadLeagues,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
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
                              HapticFeedback.selectionClick();
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
                        final isCompleted = league['status'] == 'completed';
                        return FadeInListItem(
                          index: index,
                          child: Opacity(
                            opacity: isCompleted ? 0.65 : 1.0,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.cardBorder(isDark)),
                                boxShadow: AppShadows.card(isDark),
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
                                      if (isCompleted)
                                        Container(
                                          margin: const EdgeInsets.only(
                                            left: 6,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade600,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Text(
                                            'COMPLETED',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                              letterSpacing: 0.4,
                                            ),
                                          ),
                                        ),
                                      if (league['is_private'] == true)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 6,
                                          ),
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
                                    HapticFeedback.selectionClick();
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
                                      _loadLeagues();
                                    }
                                  },
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
