// match_photo_picker.dart
// GAP-17 — shared "attach a scorecard photo" control for every score
// report/edit dialog. Extracted out of report_match_screen.dart (its
// original and, until now, only home) so the six report/edit paths that
// accept a photo share one picker implementation instead of six copies of
// the same state machine.
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../utils.dart';

class MatchPhotoPicker extends StatefulWidget {
  // Seeds the preview from an already-stored photo on an edit path — a
  // base64 data: URI, same shape decodeDataUriImage expects everywhere
  // else. Null on a fresh report, where there's nothing to seed.
  final String? initialPhotoUrl;

  // Fires with a new data: URI whenever the user picks a photo, or null
  // when they clear a photo picked *this session*. There is deliberately
  // no way to clear an already-stored [initialPhotoUrl] here — the
  // report/edit-report/edit-score routes all treat an omitted photoUrl as
  // "leave the stored photo alone" (COALESCE against the existing column),
  // not "delete it", so a remove affordance on the seeded photo would look
  // functional but silently do nothing server-side.
  final ValueChanged<String?> onChanged;

  const MatchPhotoPicker({
    super.key,
    this.initialPhotoUrl,
    required this.onChanged,
  });

  @override
  State<MatchPhotoPicker> createState() => _MatchPhotoPickerState();
}

class _MatchPhotoPickerState extends State<MatchPhotoPicker> {
  Uint8List? _initialBytes;
  Uint8List? _newBytes;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPhotoUrl;
    if (initial != null && initial.isNotEmpty) {
      _initialBytes = decodeDataUriImage(initial);
    }
  }

  Future<void> _pick() async {
    try {
      // Scorecard photos need more detail than a tiny avatar — 1024px keeps
      // it legible without ballooning past the server's request-body limit.
      final picked = await pickImageAsDataUri(
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 70,
        maxSizeBytes: 4 * 1024 * 1024,
      );
      if (picked == null) return;
      setState(() => _newBytes = picked.bytes);
      widget.onChanged(picked.dataUri);
    } on ProfileImageTooLargeException {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          title: const Text('Photo too large'),
          content: const Text('Please choose a smaller photo.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _removeNewPick() {
    setState(() => _newBytes = null);
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    if (_newBytes != null) {
      return _PhotoPreview(
        bytes: _newBytes!,
        trailing: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          tooltip: 'Remove photo',
          style: IconButton.styleFrom(backgroundColor: Colors.black45),
          onPressed: _removeNewPick,
        ),
      );
    }

    if (_initialBytes != null) {
      return _PhotoPreview(
        bytes: _initialBytes!,
        trailing: IconButton(
          icon: const Icon(Icons.edit, color: Colors.white),
          tooltip: 'Change photo',
          style: IconButton.styleFrom(backgroundColor: Colors.black45),
          onPressed: _pick,
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: _pick,
      icon: const Icon(Icons.add_a_photo_outlined),
      label: const Text('Attach a photo'),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  final Uint8List bytes;
  final Widget trailing;

  const _PhotoPreview({required this.bytes, required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            bytes,
            height: 160,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(top: 4, right: 4, child: trailing),
      ],
    );
  }
}
