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
              'This creates a fresh schedule with everyone currently in the tournament (including new joiners). '
              'Already-confirmed match results and rating changes are kept — only the fixture list itself is rebuilt.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            Text('Match Format', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: 'round_robin',
              groupValue: _scheduleType,
              title: const Text('Round Robin', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                'Everyone plays everyone. Best for 7 or fewer players.',
                style: TextStyle(fontSize: 11),
              ),
              onChanged: (v) => setState(() => _scheduleType = v!),
            ),
            if (widget.isSingles)
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: 'matches_per_player',
                groupValue: _scheduleType,
                title: const Text(
                  'Fixed matches per player',
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: const Text(
                  'Good for larger groups.',
                  style: TextStyle(fontSize: 11),
                ),
                onChanged: (v) => setState(() => _scheduleType = v!),
              ),
            if (widget.isSingles && _scheduleType == 'matches_per_player')
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: TextField(
                  controller: _matchesPerPlayerController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Matches per player',
                    isDense: true,
                  ),
                ),
              ),
            if (widget.isSingles)
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: 'knockout',
                groupValue: _scheduleType,
                title: const Text('Knockout', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  'Seeded single elimination. Needs an exact power-of-2 player count (2, 4, 8, 16...).',
                  style: TextStyle(fontSize: 11),
                ),
                onChanged: (v) => setState(() => _scheduleType = v!),
              ),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: 'custom',
              groupValue: _scheduleType,
              title: const Text('Custom', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                'You decide who plays who. Add matches manually, any time.',
                style: TextStyle(fontSize: 11),
              ),
              onChanged: (v) => setState(() => _scheduleType = v!),
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
