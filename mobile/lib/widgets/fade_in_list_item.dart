// fade_in_list_item.dart
// Small staggered fade-in for list rows as they first appear — the same
// animation my_leagues_screen.dart already used inline (TweenAnimationBuilder
// wrapping each row, with per-index delay), pulled out so other list
// screens can reuse it instead of a bare instant-appear ListView.
import 'package:flutter/material.dart';

class FadeInListItem extends StatelessWidget {
  final int index;
  final Widget child;

  const FadeInListItem({super.key, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 200 + (index * 40).clamp(0, 400)),
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: child,
    );
  }
}
