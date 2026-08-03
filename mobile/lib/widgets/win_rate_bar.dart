// win_rate_bar.dart
// A compact horizontal win/loss proportion bar — used both for a player's
// overall win rate and for a head-to-head record (in which case "wins" and
// "losses" just mean "my side" and "their side"). Replaces cramped strings
// like "62% (8-5)" or plain "3-2" text with something visual.
import 'package:flutter/material.dart';
import '../main.dart';

class WinRateBar extends StatelessWidget {
  // dynamic, not int: some backend counts are SQL SUM()/COUNT() results,
  // which Postgres returns as bigint — node-postgres parses that as a JS
  // string unless the pool overrides it (see backend/db.js), so this widget
  // tolerates either shape defensively rather than crashing on whichever
  // endpoint doesn't.
  final dynamic wins;
  final dynamic losses;
  final double height;

  const WinRateBar({
    super.key,
    required this.wins,
    required this.losses,
    this.height = 8,
  });

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final winsInt = _asInt(wins);
    final lossesInt = _asInt(losses);
    final total = winsInt + lossesInt;
    final ratio = total == 0 ? 0.0 : winsInt / total;
    final percent = (ratio * 100).round();

    return Semantics(
      label: total == 0
          ? 'No matches played yet'
          : '$winsInt wins, $lossesInt losses, $percent% win rate',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: SizedBox(
            height: height,
            child: Stack(
              children: [
                Container(
                  color: total == 0
                      ? Colors.grey.withValues(alpha: 0.2)
                      : AppColors.danger.withValues(alpha: 0.35),
                ),
                FractionallySizedBox(
                  widthFactor: ratio,
                  child: Container(color: AppColors.success),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
