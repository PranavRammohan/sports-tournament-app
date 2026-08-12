// friendly_challenge_dialog.dart
// Shared dialog for sending a friendly-match challenge — used from both
// find_players_screen.dart (Similar rating mode, sport already fixed to
// whichever sport the list was generated for) and player_profile_screen.dart
// (sport picked from whatever sports both players share). Follows the same
// "dialog collects input and pops a result map, caller does the actual API
// call" convention as this codebase's other input dialogs (e.g.
// league_detail_screen.dart's _HostReportSetsDialog) — this dialog doesn't
// know about ApiClient at all.
import 'package:flutter/material.dart';
import '../main.dart';

/// Shows the challenge dialog and returns `{sport, proposedTime, venue}` if
/// the user submitted it, or null if they cancelled. `proposedTime` is an
/// ISO-8601 string or null; `venue` is a trimmed string or null.
Future<Map<String, dynamic>?> showFriendlyChallengeDialog(
  BuildContext context, {
  required String opponentName,
  required List<String> sportOptions,
  String? presetSport,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => _FriendlyChallengeDialog(
      opponentName: opponentName,
      sportOptions: sportOptions,
      presetSport: presetSport,
    ),
  );
}

class _FriendlyChallengeDialog extends StatefulWidget {
  final String opponentName;
  final List<String> sportOptions;
  final String? presetSport;

  const _FriendlyChallengeDialog({
    required this.opponentName,
    required this.sportOptions,
    this.presetSport,
  });

  @override
  State<_FriendlyChallengeDialog> createState() =>
      _FriendlyChallengeDialogState();
}

class _FriendlyChallengeDialogState extends State<_FriendlyChallengeDialog> {
  String? _selectedSport;
  DateTime? _proposedTime;
  final TextEditingController _venueController = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedSport = widget.presetSport ?? widget.sportOptions.firstOrNull;
  }

  @override
  void dispose() {
    _venueController.dispose();
    super.dispose();
  }

  String _formatSport(String sport) => sport
      .split('_')
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _proposedTime ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 1),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_proposedTime ?? now),
    );
    if (time == null) return;
    setState(() {
      _proposedTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  String _formatDateTime(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day} · $hour12:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: Text('Challenge ${widget.opponentName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ),
            const Text(
              'A friendly match doesn\'t affect either player\'s rating or record.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            if (widget.presetSport == null)
              DropdownButtonFormField<String>(
                initialValue: _selectedSport,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Sport'),
                items: widget.sportOptions
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(_formatSport(s)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedSport = v),
              ),
            if (widget.presetSport == null) const SizedBox(height: 14),
            TextField(
              controller: _venueController,
              decoration: const InputDecoration(
                labelText: 'Venue (optional)',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(
                _proposedTime == null
                    ? 'Propose a time (optional)'
                    : _formatDateTime(_proposedTime!),
              ),
              trailing: _proposedTime == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      tooltip: 'Clear',
                      onPressed: () => setState(() => _proposedTime = null),
                    ),
              onTap: _pickTime,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_selectedSport == null) {
              setState(() => _error = 'Please choose a sport.');
              return;
            }
            Navigator.pop(context, {
              'sport': _selectedSport,
              'proposedTime': _proposedTime?.toIso8601String(),
              'venue': _venueController.text.trim().isEmpty
                  ? null
                  : _venueController.text.trim(),
            });
          },
          child: const Text('Send Challenge'),
        ),
      ],
    );
  }
}
