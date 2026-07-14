// schedule_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

const String apiUrl = 'http://localhost:3000/api';

class ScheduleScreen extends StatefulWidget {
  final int leagueId;
  final bool isHost;

  const ScheduleScreen({
    super.key,
    required this.leagueId,
    required this.isHost,
  });

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  List<dynamic> _schedule = [];
  bool _loading = true;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.get(
        Uri.parse('$apiUrl/leagues/${widget.leagueId}/schedule'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        setState(() => _schedule = data['schedule']);
      }
    } catch (err) {
      // fail silently, pull-to-refresh available
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _generateSchedule() async {
    setState(() => _generating = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.post(
        Uri.parse('$apiUrl/leagues/${widget.leagueId}/generate-schedule'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;
      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Schedule generated: ${data['matchCount']} matches'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadSchedule();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not generate schedule.'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Network error.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  String _formatSetScores(dynamic rawSetScores) {
    if (rawSetScores == null) return '';
    try {
      final List sets = jsonDecode(rawSetScores);
      if (sets.isEmpty) return '';
      return sets.map((s) => '${s['me']}-${s['opponent']}').join(', ');
    } catch (err) {
      return '';
    }
  }

  Map<int, List<dynamic>> _groupByTier() {
    final Map<int, List<dynamic>> grouped = {};
    for (final fixture in _schedule) {
      final tier = fixture['tier_number'];
      grouped.putIfAbsent(tier, () => []).add(fixture);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final tiers = _groupByTier();

    return Scaffold(
      appBar: AppBar(title: const Text('Schedule')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSchedule,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_schedule.isEmpty) ...[
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.4,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              widget.isHost
                                  ? 'No schedule yet. Generate one to get started.'
                                  : "The host hasn't generated a schedule yet.",
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            if (widget.isHost) ...[
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _generating
                                    ? null
                                    : _generateSchedule,
                                child: _generating
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : const Text('Generate Schedule'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ] else
                    ...tiers.entries.map((entry) {
                      final tierNumber = entry.key;
                      final fixtures = entry.value;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tier $tierNumber',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 10),
                            ...fixtures.map((f) {
                              final isDoubles =
                                  f['player1_partner_username'] != null;
                              final team1 = isDoubles
                                  ? '${f['player1_username']} & ${f['player1_partner_username']}'
                                  : f['player1_username'];
                              final team2 = isDoubles
                                  ? '${f['player2_username']} & ${f['player2_partner_username']}'
                                  : f['player2_username'];

                              final isCompleted =
                                  f['match_status'] == 'confirmed';
                              final team1Won =
                                  isCompleted &&
                                  f['winner_id'] == f['reported_player1_id'];
                              final team2Won =
                                  isCompleted &&
                                  f['winner_id'] == f['reported_player2_id'];

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isCompleted
                                        ? AppColors.success.withValues(
                                            alpha: 0.4,
                                          )
                                        : Colors.grey.shade200,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Wrap(
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                team1,
                                                style: TextStyle(
                                                  fontWeight: team1Won
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  color: team1Won
                                                      ? AppColors.success
                                                      : null,
                                                ),
                                              ),
                                              const Text('  vs  '),
                                              Text(
                                                team2,
                                                style: TextStyle(
                                                  fontWeight: team2Won
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  color: team2Won
                                                      ? AppColors.success
                                                      : null,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isCompleted
                                                ? AppColors.success.withValues(
                                                    alpha: 0.12,
                                                  )
                                                : AppColors.accent.withValues(
                                                    alpha: 0.12,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            isCompleted
                                                ? 'Completed'
                                                : 'Pending',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: isCompleted
                                                  ? AppColors.success
                                                  : AppColors.accent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (isCompleted) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatSetScores(f['set_scores']),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
