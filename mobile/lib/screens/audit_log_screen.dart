// audit_log_screen.dart
// GAP-14 — "activity log" for a tournament, host/co-host only. Read-only view
// of backend/audit.js's league_audit_log rows: who did what destructive
// action and when. Not a full before/after diff — just enough to answer
// "who did this."
import 'package:flutter/material.dart';
import '../api_client.dart';
import '../date_utils.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/friendly_empty_state.dart';

const Map<String, String> _auditActionLabels = {
  'edit_score': 'Edited a confirmed score',
  'delete_match': 'Deleted a match',
  'remove_player': 'Removed a player',
  'regenerate_schedule': 'Regenerated the schedule',
  'delete_group': 'Deleted a group',
  'unlock_group': 'Unlocked a group',
  'unassign_from_group': 'Removed a player from a group',
  'edit_fixture': 'Edited a scheduled match',
  'delete_fixture': 'Deleted a scheduled match',
  'grant_co_host': 'Granted co-host status',
  'revoke_co_host': 'Revoked co-host status',
  'cancel_bracket': 'Removed the playoff bracket',
  'edit_playoff_score': 'Edited a confirmed playoff score',
};

class AuditLogScreen extends StatefulWidget {
  final int leagueId;

  const AuditLogScreen({super.key, required this.leagueId});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  List<dynamic> _entries = [];
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
      final res = await ApiClient.get('/leagues/${widget.leagueId}/audit');
      if (res.statusCode == 200) {
        setState(() => _entries = res.data['entries']);
      } else {
        setState(() => _error = res.errorOr('Could not load the activity log.'));
      }
    } catch (err) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activity Log')),
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
          : _entries.isEmpty
          ? const FriendlyEmptyState(
              icon: Icons.history,
              title: 'No activity yet.',
              subtitle: 'Destructive actions — edits, removals, schedule changes — will show up here.',
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _entries.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  final label = _auditActionLabels[entry['action']] ?? entry['action'];
                  return ListTile(
                    leading: const Icon(Icons.history, size: 20),
                    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      [
                        if (entry['summary'] != null) entry['summary'],
                        '${entry['actor_username'] ?? 'Unknown'} · ${formatRelativeTime(entry['created_at'])}',
                      ].join('\n'),
                    ),
                    isThreeLine: entry['summary'] != null,
                  );
                },
              ),
            ),
    );
  }
}
