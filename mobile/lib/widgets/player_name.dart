// player_name.dart
// Deferred mobile UI item: "tappable names app-wide." Before this, a name
// was only tappable in the leaderboard and player search — every fixture,
// roster, group standing, and bracket slot showed an inert Text. This
// widget is a drop-in replacement for those plain Text(name) call sites:
// tap opens PlayerProfileScreen, and it quietly degrades to plain text when
// there's no real profile to open (no id, or a guest — guests have no
// meaningful profile to view).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../screens/player_profile_screen.dart';

class PlayerName extends StatelessWidget {
  final int? userId;
  final String name;
  final TextStyle? style;
  final bool isGuest;
  final TextOverflow? overflow;
  final int? maxLines;

  const PlayerName({
    super.key,
    required this.userId,
    required this.name,
    this.style,
    this.isGuest = false,
    this.overflow,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      name,
      style: style,
      overflow: overflow,
      maxLines: maxLines,
    );

    if (userId == null || isGuest) return text;

    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlayerProfileScreen(userId: userId!),
          ),
        );
      },
      child: text,
    );
  }
}
