// win_rate_bar.dart
// A compact horizontal win/loss proportion bar — used both for a player's
// overall win rate and for a head-to-head record (in which case "wins" and
// "losses" just mean "my side" and "their side"). Replaces cramped strings
// like "62% (8-5)" or plain "3-2" text with something visual.
import 'package:flutter/material.dart';
import '../main.dart';

class WinRateBar extends StatelessWidget {
  final int wins;
  final int losses;
  final double height;

  const WinRateBar({
    super.key,
    required this.wins,
    required this.losses,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    final total = wins + losses;
    final ratio = total == 0 ? 0.0 : wins / total;

    return ClipRRect(
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
    );
  }
}
