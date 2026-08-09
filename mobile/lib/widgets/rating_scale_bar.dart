// rating_scale_bar.dart
// A horizontal "where you stand" visual for a sport's rating scale — the
// track spans that sport's practical min-to-pro range (sportLevels in
// constants/sports.dart), small ticks mark each skill-level threshold, and
// a dot marks the player's actual current rating. Renders nothing for a
// sport with no known range (defensive — every real sport key has one).
import 'package:flutter/material.dart';
import '../constants/sports.dart';
import '../main.dart';
import '../utils.dart';

class RatingScaleBar extends StatelessWidget {
  final String sport; // snake_case backend key, e.g. 'table_tennis'
  final dynamic rating;

  const RatingScaleBar({super.key, required this.sport, required this.rating});

  @override
  Widget build(BuildContext context) {
    final ratingValue = rating is num ? rating as num : num.tryParse(rating.toString());
    final range = sportRatingRange(sport);
    final levels = sportLevelsFor(sport);
    if (ratingValue == null || range == null || levels == null) {
      return const SizedBox.shrink();
    }

    final min = range.min.toDouble();
    final max = range.max.toDouble();
    final span = max - min;
    if (span <= 0) return const SizedBox.shrink();

    final clamped = ratingValue.toDouble().clamp(min, max);
    final position = (clamped - min) / span;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor = isDark ? Colors.grey.shade800 : Colors.grey.shade300;
    final tickColor = isDark ? Colors.grey.shade600 : Colors.grey.shade400;
    final markerRingColor = isDark ? AppColors.darkSurface : Colors.white;
    final band = ratingBandFor(sport, ratingValue);

    return Semantics(
      label:
          'Rating scale: ${formatRating(sport, ratingValue)}'
          '${band != null ? ', $band' : ''}, '
          'out of a range from ${range.min} to ${range.max}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 26,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: 11,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: trackColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      for (final entry in levels.entries)
                        Positioned(
                          left:
                              (width * ((entry.value - min) / span)).clamp(0.0, width) -
                              1,
                          top: 8,
                          child: Container(width: 2, height: 10, color: tickColor),
                        ),
                      Positioned(
                        left: (width * position).clamp(0.0, width) - 7,
                        top: 6,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                            border: Border.all(color: markerRingColor, width: 2),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 2,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formatRating(sport, range.min),
                  style: TextStyle(fontSize: 9, color: tickColor),
                ),
                Text(
                  formatRating(sport, range.max),
                  style: TextStyle(fontSize: 9, color: tickColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
