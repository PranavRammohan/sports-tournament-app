// player_avatar.dart
// Shared read-only avatar: a player's profile picture, or an initial-letter
// fallback when they don't have one. Replaces five near-identical ad hoc
// CircleAvatar implementations that used to be scattered across
// home_screen.dart, profile_screen.dart, player_profile_screen.dart, and
// league_detail_screen.dart — none of which cached images or handled a
// broken/slow URL gracefully. Uses cached_network_image for both.
//
// Not used by edit_profile_screen.dart, which has its own editable avatar
// (local file preview + camera-icon overlay for changing the photo) — a
// meaningfully different widget, not a plain display avatar.
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../main.dart';

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
    final hasPic = profilePicUrl != null && profilePicUrl!.isNotEmpty;
    final bg = backgroundColor ?? AppColors.primary.withValues(alpha: 0.15);
    final fg = foregroundColor ?? AppColors.primary;
    final initialStyle = TextStyle(
      fontSize: radius * 0.8,
      fontWeight: FontWeight.bold,
      color: fg,
    );

    if (!hasPic) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: Text(_initial, style: initialStyle),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: profilePicUrl!,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          placeholder: (context, url) => SizedBox(
            width: radius,
            height: radius,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          ),
          errorWidget: (context, url, error) =>
              Text(_initial, style: initialStyle),
        ),
      ),
    );
  }
}
