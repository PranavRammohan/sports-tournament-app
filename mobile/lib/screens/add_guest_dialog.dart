// add_guest_dialog.dart
// Lets a host add a player who hasn't signed up — GAP-05 (the "non-users
// can't be added at all" half) from the codebase audit. The backend gives
// the guest a real (login-less) users row, so this is really a small
// host-driven stand-in for signup: a name and a skill level, same as
// select_sports_screen.dart asks a real signup for.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../api_client.dart';
import '../constants/sports.dart';

class AddGuestDialog extends StatefulWidget {
  final int leagueId;
  final String sport;

  const AddGuestDialog({super.key, required this.leagueId, required this.sport});

  @override
  State<AddGuestDialog> createState() => _AddGuestDialogState();
}

class _AddGuestDialogState extends State<AddGuestDialog> {
  final TextEditingController _nameController = TextEditingController();
  String? _level;
  String? _error;
  bool _submitting = false;

  // sportLevels (constants/sports.dart) is keyed by the Title Case display
  // name ("Table Tennis"), but the league's sport is stored/sent in the
  // backend's snake_case form ("table_tennis") — same reverse transform
  // pending_matches_screen.dart's _formatSport already uses elsewhere.
  String get _sportLabel => widget.sport
      .split('_')
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = "Please enter the guest's name.");
      return;
    }
    if (_level == null) {
      setState(() => _error = "Please select the guest's skill level.");
      return;
    }

    HapticFeedback.lightImpact();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await ApiClient.post(
        '/leagues/${widget.leagueId}/add-guest',
        body: {'guestName': name, 'skillLevel': _level},
      );
      if (!mounted) return;
      if (res.statusCode == 201) {
        Navigator.pop(context, true);
      } else {
        setState(() => _error = res.errorOr('Could not add guest.'));
      }
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: const Text('Add Guest'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "For a player who hasn't signed up yet. They'll appear in the "
              "roster tagged as a guest and can't confirm their own scores — "
              "use host-entered scoring for their matches.",
              style: TextStyle(fontSize: 12, color: AppColors.textGrey),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Guest name',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _level,
              decoration: const InputDecoration(
                labelText: 'Skill level',
                isDense: true,
              ),
              items: (sportLevels[_sportLabel]?.keys ?? const <String>[])
                  .map(
                    (level) => DropdownMenuItem(
                      value: level,
                      child: Text(capitalizeLevel(level)),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _level = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Add'),
        ),
      ],
    );
  }
}
