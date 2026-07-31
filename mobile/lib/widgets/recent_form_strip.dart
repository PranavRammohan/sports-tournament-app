// recent_form_strip.dart
// A row of small colored dots summarizing a player's last few results —
// oldest on the left, most recent on the right (the usual sports "form
// guide" reading order).
import 'package:flutter/material.dart';
import '../main.dart';

class RecentFormStrip extends StatelessWidget {
  final List<bool> results; // chronological order, oldest first
  final double dotSize;

  const RecentFormStrip({
    super.key,
    required this.results,
    this.dotSize = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final won in results)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: won ? AppColors.success : AppColors.danger,
              ),
            ),
          ),
      ],
    );
  }
}
