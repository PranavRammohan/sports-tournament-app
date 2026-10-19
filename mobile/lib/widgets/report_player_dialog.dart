// report_player_dialog.dart
// Shared dialog for reporting a player — used from player_profile_screen.
// dart. Same "dialog collects input and pops a result map, caller does the
// actual API call" convention as friendly_challenge_dialog.dart.
import 'package:flutter/material.dart';
import '../main.dart';

const Map<String, String> reportReasonLabels = {
  'harassment': 'Harassment',
  'inappropriate_behavior': 'Inappropriate behavior',
  'no_show': "Didn't show up / no-show",
  'other': 'Other',
};

/// Shows the report dialog and returns `{reason, details, alsoBlock}` if
/// submitted, or null if cancelled. `details` is a trimmed string or null.
Future<Map<String, dynamic>?> showReportPlayerDialog(
  BuildContext context, {
  required String playerName,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => _ReportPlayerDialog(playerName: playerName),
  );
}

class _ReportPlayerDialog extends StatefulWidget {
  final String playerName;

  const _ReportPlayerDialog({required this.playerName});

  @override
  State<_ReportPlayerDialog> createState() => _ReportPlayerDialogState();
}

class _ReportPlayerDialogState extends State<_ReportPlayerDialog> {
  String? _reason;
  bool _alsoBlock = true;
  final TextEditingController _detailsController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: Text('Report ${widget.playerName}'),
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
            ...reportReasonLabels.entries.map(
              (entry) => RadioListTile<String>(
                value: entry.key,
                groupValue: _reason,
                onChanged: (v) => setState(() => _reason = v),
                title: Text(entry.value),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _detailsController,
              maxLines: 3,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Details (optional)',
                alignLabelWithHint: true,
              ),
            ),
            CheckboxListTile(
              value: _alsoBlock,
              onChanged: (v) => setState(() => _alsoBlock = v ?? false),
              title: const Text('Also block this player'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
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
            if (_reason == null) {
              setState(() => _error = 'Please choose a reason.');
              return;
            }
            Navigator.pop(context, {
              'reason': _reason,
              'details': _detailsController.text.trim().isEmpty
                  ? null
                  : _detailsController.text.trim(),
              'alsoBlock': _alsoBlock,
            });
          },
          child: const Text('Submit Report'),
        ),
      ],
    );
  }
}
