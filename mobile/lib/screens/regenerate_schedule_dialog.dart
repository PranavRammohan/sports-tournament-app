// regenerate_schedule_dialog.dart
import 'package:flutter/material.dart';

class RegenerateScheduleResult {
  final String? scheduleType;
  final int? matchesPerPlayer;

  RegenerateScheduleResult({this.scheduleType, this.matchesPerPlayer});
}

class RegenerateScheduleDialog extends StatefulWidget {
  final String currentScheduleType;
  final int? currentMatchesPerPlayer;
  final bool isSingles;

  const RegenerateScheduleDialog({
    super.key,
    required this.currentScheduleType,
    required this.currentMatchesPerPlayer,
    required this.isSingles,
  });

  @override
  State<RegenerateScheduleDialog> createState() =>
      _RegenerateScheduleDialogState();
}

class _RegenerateScheduleDialogState extends State<RegenerateScheduleDialog> {
  late String _scheduleType;
  late final TextEditingController _matchesPerPlayerController;

  @override
  void initState() {
    super.initState();
    _scheduleType = widget.currentScheduleType;
    _matchesPerPlayerController = TextEditingController(
      text: widget.currentMatchesPerPlayer?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _matchesPerPlayerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: const Text('Change Match Format'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This wipes all match history for this tournament — every confirmed result, rating change, and point awarded so far will be reversed — and builds a fresh, all-pending fixture list with everyone currently in the tournament (including new joiners). This cannot be undone.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            Text('Match Format', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            RadioGroup<String>(
              groupValue: _scheduleType,
              onChanged: (v) => setState(() => _scheduleType = v!),
              child: Column(
                children: [
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: 'round_robin',
                    title: const Text(
                      'Round Robin',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Everyone plays everyone. Best for smaller groups — match count grows fast as more people join.',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: 'matches_per_player',
                    title: Text(
                      widget.isSingles
                          ? 'Fixed matches per player'
                          : 'Fixed matches per team',
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Good for larger groups.',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                  if (_scheduleType == 'matches_per_player')
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: TextField(
                        controller: _matchesPerPlayerController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: widget.isSingles
                              ? 'Matches per player'
                              : 'Matches per team',
                          isDense: true,
                        ),
                      ),
                    ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: 'knockout',
                    title: const Text('Knockout', style: TextStyle(fontSize: 14)),
                    subtitle: Text(
                      widget.isSingles
                          ? 'Seeded single elimination. Needs an exact power-of-2 player count (2, 4, 8, 16...).'
                          : 'Seeded single elimination. Needs an exact power-of-2 number of teams (2, 4, 8, 16...).',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: 'custom',
                    title: const Text('Custom', style: TextStyle(fontSize: 14)),
                    subtitle: const Text(
                      'You decide who plays who. Add matches manually, any time.',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: 'groups',
                    title: const Text('Groups', style: TextStyle(fontSize: 14)),
                    subtitle: Text(
                      widget.isSingles
                          ? 'Create named groups any time, pick who\'s in each one, and choose that group\'s own format afterward.'
                          : 'Create named groups any time, pick which teams are in each one, and choose that group\'s own format afterward. Needs self-select or host-assigns partner mode (not automatic).',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
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
            int? matchesPerPlayer;
            if (_scheduleType == 'matches_per_player') {
              matchesPerPlayer = int.tryParse(
                _matchesPerPlayerController.text.trim(),
              );
              if (matchesPerPlayer == null || matchesPerPlayer < 1) return;
            }
            Navigator.pop(
              context,
              RegenerateScheduleResult(
                scheduleType: _scheduleType,
                matchesPerPlayer: matchesPerPlayer,
              ),
            );
          },
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
