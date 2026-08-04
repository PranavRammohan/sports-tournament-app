// match_photo_thumbnail.dart
// GAP-17 — a small thumbnail for a match's attached scorecard photo (stored
// as a base64 data-URI, same as profile pictures), tap to view full-screen.
// Renders nothing if the match has no photo, so callers can drop it in
// unconditionally.
import 'package:flutter/material.dart';
import '../utils.dart';

class MatchPhotoThumbnail extends StatelessWidget {
  final String? photoUrl;
  final double size;

  const MatchPhotoThumbnail({super.key, required this.photoUrl, this.size = 40});

  @override
  Widget build(BuildContext context) {
    if (photoUrl == null || photoUrl!.isEmpty) return const SizedBox.shrink();
    final bytes = decodeDataUriImage(photoUrl!);
    if (bytes == null) return const SizedBox.shrink();

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        showDialog(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.black,
            insetPadding: const EdgeInsets.all(12),
            child: GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: InteractiveViewer(
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
