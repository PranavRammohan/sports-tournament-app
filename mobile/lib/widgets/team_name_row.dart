// team_name_row.dart
// Renders one side of a fixture, bracket match, or standings row — a single
// player, or "A & B" for doubles — with each player's name individually
// tappable via PlayerName. Kept separate from PlayerName itself because a
// "team" can be one or two players and needs the "&" joiner plus a second
// id/guest flag, neither of which a single PlayerName call site has.
import 'package:flutter/material.dart';
import 'player_name.dart';

class TeamNameRow extends StatelessWidget {
  final int? playerId;
  final String playerName;
  final int? partnerId;
  final String? partnerName;
  final bool isGuest;
  final bool partnerIsGuest;
  final TextStyle? style;
  // Optional trailing text appended after the (singles) player's name, e.g.
  // a rating suffix like " (1500)" — kept outside the tap target on
  // purpose, since it's metadata about the player, not part of their name.
  final String? suffix;

  const TeamNameRow({
    super.key,
    required this.playerId,
    required this.playerName,
    this.partnerId,
    this.partnerName,
    this.isGuest = false,
    this.partnerIsGuest = false,
    this.style,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Flexible(
        child: PlayerName(
          userId: playerId,
          name: playerName,
          isGuest: isGuest,
          style: style,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ];
    if (partnerName != null) {
      children.add(Text(' & ', style: style));
      children.add(
        Flexible(
          child: PlayerName(
            userId: partnerId,
            name: partnerName!,
            isGuest: partnerIsGuest,
            style: style,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    } else if (suffix != null) {
      children.add(Text(suffix!, style: style));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}
