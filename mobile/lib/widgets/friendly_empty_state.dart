// friendly_empty_state.dart
// A warmer empty-state widget with a layered icon illustration, a friendly
// message, and an optional action button — used across the app instead of
// bare gray text or a plain flat icon.
import 'package:flutter/material.dart';
import '../main.dart';

class FriendlyEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const FriendlyEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark;
    final subtitleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Layered illustration: a soft outer ring behind a filled inner
            // circle, instead of a single flat circle — gives more depth
            // without needing real custom artwork.
            SizedBox(
              width: 108,
              height: 108,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 108,
                    height: 108,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(
                        alpha: isDark ? 0.08 : 0.04,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(
                        alpha: isDark ? 0.18 : 0.07,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Icon(
                    icon,
                    size: 38,
                    color: AppColors.accent.withValues(
                      alpha: isDark ? 0.95 : 0.75,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: titleColor,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: subtitleColor),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              TextButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
