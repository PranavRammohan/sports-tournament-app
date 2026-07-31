// partner_selection_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../config.dart';
import '../widgets/loading_skeleton.dart';

// Handles both doubles partner-selection flows:
// - 'self_select': players send/accept/decline partner requests themselves
// - 'host_manual': the host pairs everyone from a simple dropdown UI
// 'host_auto' leagues never navigate here (see league_detail_screen.dart).
class PartnerSelectionScreen extends StatefulWidget {
  final int leagueId;
  final String partnerMode;
  final bool isHost;
  final int? currentUserId;

  const PartnerSelectionScreen({
    super.key,
    required this.leagueId,
    required this.partnerMode,
    required this.isHost,
    required this.currentUserId,
  });

  @override
  State<PartnerSelectionScreen> createState() => _PartnerSelectionScreenState();
}

class _PartnerSelectionScreenState extends State<PartnerSelectionScreen> {
  List<dynamic> _members = [];
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  // Host-manual: currently-selected pair-in-progress.
  int? _selectedA;
  int? _selectedB;

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
      final res = await http.get(
        Uri.parse('$baseApiUrl/leagues/${widget.leagueId}/partners'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        setState(() => _members = data['members']);
      } else {
        setState(
          () => _error = data['error'] ?? 'Could not load partner status.',
        );
      }
    } catch (err) {
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? get _myRow {
    for (final m in _members) {
      if (m['id'] == widget.currentUserId) return m;
    }
    return null;
  }

  // Rows belonging to other members who have sent ME a pending request
  // (their partner_id points at me, status pending).
  List<dynamic> get _incomingRequests => _members
      .where(
        (m) =>
            m['partner_id'] == widget.currentUserId &&
            m['partner_status'] == 'pending',
      )
      .toList();

  List<dynamic> get _availableToRequest {
    final busyIds = <int>{};
    for (final m in _members) {
      if (m['partner_status'] != null) {
        busyIds.add(m['id'] as int);
        if (m['partner_id'] != null) busyIds.add(m['partner_id'] as int);
      }
    }
    return _members
        .where(
          (m) => m['id'] != widget.currentUserId && !busyIds.contains(m['id']),
        )
        .toList();
  }

  Future<void> _sendRequest(int partnerId) async {
    HapticFeedback.lightImpact();
    setState(() => _submitting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final res = await http.post(
        Uri.parse('$baseApiUrl/leagues/${widget.leagueId}/select-partner'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'partnerId': partnerId}),
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Request sent.'),
            backgroundColor: AppColors.success,
          ),
        );
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not send request.'),
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
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _respond(int requesterId, bool accept) async {
    HapticFeedback.lightImpact();
    setState(() => _submitting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final res = await http.post(
        Uri.parse('$baseApiUrl/leagues/${widget.leagueId}/respond-partner'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'accept': accept, 'requesterId': requesterId}),
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Done.'),
            backgroundColor: AppColors.success,
          ),
        );
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not respond.'),
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
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _unpair({int? targetUserId}) async {
    HapticFeedback.mediumImpact();
    setState(() => _submitting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final res = await http.post(
        Uri.parse('$baseApiUrl/leagues/${widget.leagueId}/unpair'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({if (targetUserId != null) 'userId': targetUserId}),
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Removed.'),
            backgroundColor: AppColors.success,
          ),
        );
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not unpair.'),
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
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _assignPair() async {
    if (_selectedA == null || _selectedB == null || _selectedA == _selectedB) {
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _submitting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final res = await http.post(
        Uri.parse('$baseApiUrl/leagues/${widget.leagueId}/assign-partner'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'player1Id': _selectedA, 'player2Id': _selectedB}),
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Paired.'),
            backgroundColor: AppColors.success,
          ),
        );
        setState(() {
          _selectedA = null;
          _selectedB = null;
        });
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? 'Could not pair.'),
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
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Partners')),
      body: _loading
          ? const SkeletonList()
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: widget.partnerMode == 'host_manual' && widget.isHost
                  ? _buildHostManualView()
                  : _buildSelfSelectView(),
            ),
    );
  }

  Widget _buildSelfSelectView() {
    final myRow = _myRow;
    final myStatus = myRow?['partner_status'];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (myStatus == 'confirmed') ...[
          _sectionTitle('Your Partner'),
          _memberCard(
            title: myRow!['partner_username'] ?? '',
            subtitle: 'Confirmed partner',
            trailing: TextButton(
              onPressed: _submitting ? null : () => _unpair(),
              child: const Text(
                'Unpair',
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ),
        ] else if (myStatus == 'pending') ...[
          _sectionTitle('Waiting for confirmation'),
          _memberCard(
            title: myRow!['partner_username'] ?? '',
            subtitle: 'Waiting for them to accept your request',
            trailing: TextButton(
              onPressed: _submitting ? null : () => _unpair(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ),
        ] else ...[
          if (_incomingRequests.isNotEmpty) ...[
            _sectionTitle('Partner Requests'),
            ..._incomingRequests.map(
              (r) => _memberCard(
                title: r['username'],
                subtitle: 'Wants to be your partner',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => _respond(r['id'] as int, false),
                      child: const Text(
                        'Decline',
                        style: TextStyle(color: AppColors.danger),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _submitting
                          ? null
                          : () => _respond(r['id'] as int, true),
                      child: const Text('Accept'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _sectionTitle('Choose a Partner'),
          if (_availableToRequest.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No available players to pair with right now.'),
            )
          else
            ..._availableToRequest.map(
              (m) => _memberCard(
                title: m['username'],
                trailing: ElevatedButton(
                  onPressed: _submitting ? null : () => _sendRequest(m['id']),
                  child: const Text('Request'),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildHostManualView() {
    final unpaired = _members
        .where((m) => m['partner_status'] != 'confirmed')
        .toList();
    final pairedSeen = <int>{};
    final pairs = <List<dynamic>>[];
    for (final m in _members) {
      if (m['partner_status'] == 'confirmed' && !pairedSeen.contains(m['id'])) {
        dynamic partner;
        for (final x in _members) {
          if (x['id'] == m['partner_id']) {
            partner = x;
            break;
          }
        }
        pairedSeen.add(m['id'] as int);
        if (partner != null) pairedSeen.add(partner['id'] as int);
        pairs.add([m, partner]);
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (pairs.isNotEmpty) ...[
          _sectionTitle('Confirmed Pairs'),
          ...pairs.map(
            (p) => _memberCard(
              title: '${p[0]['username']} & ${p[1]?['username'] ?? '—'}',
              trailing: TextButton(
                onPressed: _submitting
                    ? null
                    : () => _unpair(targetUserId: p[0]['id']),
                child: const Text(
                  'Unpair',
                  style: TextStyle(color: AppColors.danger),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _sectionTitle('Pair Remaining Players'),
        if (unpaired.length < 2)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Everyone is paired.'),
          )
        else ...[
          DropdownButtonFormField<int>(
            initialValue: _selectedA,
            decoration: const InputDecoration(labelText: 'Player 1'),
            items: unpaired
                .map<DropdownMenuItem<int>>(
                  (m) => DropdownMenuItem(
                    value: m['id'] as int,
                    child: Text(m['username']),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _selectedA = v),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: _selectedB,
            decoration: const InputDecoration(labelText: 'Player 2'),
            items: unpaired
                .where((m) => m['id'] != _selectedA)
                .map<DropdownMenuItem<int>>(
                  (m) => DropdownMenuItem(
                    value: m['id'] as int,
                    child: Text(m['username']),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _selectedB = v),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: (_selectedA == null || _selectedB == null || _submitting)
                ? null
                : _assignPair,
            child: const Text('Pair These Players'),
          ),
        ],
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _memberCard({
    required String title,
    String? subtitle,
    Widget? trailing,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder(isDark)),
        boxShadow: AppShadows.card(isDark),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle != null
            ? Text(subtitle, style: const TextStyle(fontSize: 12))
            : null,
        trailing: trailing,
      ),
    );
  }
}
