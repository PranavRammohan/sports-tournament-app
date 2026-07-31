// match_badges.dart
// Small shared widgets for the match-result visual language that used to be
// hand-rolled slightly differently in home_screen.dart, player_profile_screen.dart,
// league_detail_screen.dart, and groups_overview_screen.dart — a filled WIN/LOSS
// pill, a colored rating-change delta, and the accent-colored points readout.
// Consolidating them means every screen that shows a match result or a
// player's points looks the same, and a future style tweak only happens once.
import 'package:flutter/material.dart';
import '../main.dart';

/// Filled colored pill reading "WIN" or "LOSS". `dense` shrinks it for
/// tighter list rows (e.g. a compact match-history line) — default size
/// matches the original home_screen.dart treatment.
class WinLossPill extends StatelessWidget {
  final bool won;
  final bool dense;

  const WinLossPill({super.key, required this.won, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final color = won ? AppColors.success : AppColors.danger;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(dense ? 4 : 6),
      ),
      child: Text(
        won ? 'WIN' : 'LOSS',
        style: TextStyle(
          color: Colors.white,
          fontSize: dense ? 9 : 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// A rating change like "+1.23" (green) or "-0.87" (red). Renders nothing
/// when `delta` is null (e.g. a match predating rating-change tracking).
class RatingDeltaText extends StatelessWidget {
  final double? delta;
  final double fontSize;
  final int decimalDigits;

  const RatingDeltaText({
    super.key,
    required this.delta,
    this.fontSize = 14,
    this.decimalDigits = 2,
  });

  @override
  Widget build(BuildContext context) {
    final d = delta;
    if (d == null) return const SizedBox.shrink();
    final positive = d >= 0;
    return Text(
      '${positive ? '+' : ''}${d.toStringAsFixed(decimalDigits)}',
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        color: positive ? AppColors.success : AppColors.danger,
      ),
    );
  }
}

/// The accent-colored "N pts" readout used on leaderboards/standings.
class PointsBadge extends StatelessWidget {
  final num points;
  final double fontSize;

  const PointsBadge({super.key, required this.points, this.fontSize = 15});

  @override
  Widget build(BuildContext context) {
    return Text(
      '$points pts',
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        color: AppColors.accent,
      ),
    );
  }
}
