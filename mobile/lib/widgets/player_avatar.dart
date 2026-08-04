// player_avatar.dart
// Shared read-only avatar: a player's profile picture, or an initial-letter
// fallback when they don't have one. Replaces five near-identical ad hoc
// CircleAvatar implementations that used to be scattered across
// home_screen.dart, profile_screen.dart, player_profile_screen.dart, and
// league_detail_screen.dart.
//
// profilePicUrl is always a base64 data: URI, never a real hosted URL (see
// utils.dart's decodeDataUriImage) — this renders it via Image.memory, not
// a network image widget. NetworkImage/CachedNetworkImage only appeared to
// work here on Flutter Web (which delegates image decoding to the browser,
// and browsers understand data: URLs); on Android/iOS they fetch through a
// real HTTP client, which has no data: scheme support, so the photo silently
// fell back to the initials avatar on every phone build.
//
// Not used by edit_profile_screen.dart, which has its own editable avatar
// (local file preview + camera-icon overlay for changing the photo) — a
// meaningfully different widget, not a plain display avatar.
import 'package:flutter/material.dart';
import '../main.dart';
import '../utils.dart';

class PlayerAvatar extends StatelessWidget {
  final String username;
  final String? profilePicUrl;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const PlayerAvatar({
    super.key,
    required this.username,
    this.profilePicUrl,
    this.radius = 20,
    this.backgroundColor,
    this.foregroundColor,
  });

  String get _initial => username.isNotEmpty ? username[0].toUpperCase() : '?';

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? AppColors.primary.withValues(alpha: 0.15);
    final fg = foregroundColor ?? AppColors.primary;
    final initialStyle = TextStyle(
      fontSize: radius * 0.8,
      fontWeight: FontWeight.bold,
      color: fg,
    );

    final bytes = (profilePicUrl != null && profilePicUrl!.isNotEmpty)
        ? decodeDataUriImage(profilePicUrl!)
        : null;

    if (bytes == null) {
      return Semantics(
        label: "$username's avatar",
        image: true,
        child: CircleAvatar(
          radius: radius,
          backgroundColor: bg,
          child: Text(_initial, style: initialStyle),
        ),
      );
    }

    return Semantics(
      label: "$username's avatar",
      image: true,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: ClipOval(
          child: Image.memory(
            bytes,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                Text(_initial, style: initialStyle),
          ),
        ),
      ),
    );
  }
}
