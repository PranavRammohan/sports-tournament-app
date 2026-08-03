// sport_icon.dart
// Shared helper for showing a sport's icon consistently across the app.
// Badminton/Tennis/Table Tennis render as emoji by default (they render
// fine in their natural multi-color form) — but a plain emoji Text widget
// ignores any `color:` override, so it could never be tinted to match a
// badge/chip's accent color. When a `color` IS passed, tennis switches to
// the real Material `sports_tennis` icon (a proper tintable vector), and
// the other emoji get wrapped in a ColorFiltered srcIn tint that turns the
// glyph into a solid silhouette of that color — same trick used for any
// icon font, applied to emoji. Pickleball has no emoji at all, so it's
// always the hand-drawn PickleballIcon below, which now also honors an
// optional single-color override the same way.
import 'package:flutter/material.dart';

const Map<String, String> _sportEmojis = {
  'badminton': '🏸',
  'tennis': '🎾',
  'table_tennis': '🏓',
};

String _sportSemanticLabel(String key) => key
    .split('_')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
    .join(' ');

Widget sportIcon(String sportKey, {double size = 20, Color? color}) {
  final key = sportKey.toLowerCase().replaceAll(' ', '_');
  final label = _sportSemanticLabel(key);

  if (key == 'pickleball') {
    return Semantics(
      label: label,
      child: PickleballIcon(size: size, color: color),
    );
  }

  if (key == 'tennis' && color != null) {
    return Icon(Icons.sports_tennis, size: size, color: color, semanticLabel: label);
  }

  final emoji = Text(_sportEmojis[key] ?? '🏅', style: TextStyle(fontSize: size));
  final iconWidget = color == null
      ? emoji
      : ColorFiltered(
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          child: emoji,
        );
  return Semantics(label: label, excludeSemantics: true, child: iconWidget);
}

class PickleballIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const PickleballIcon({super.key, this.size = 20, this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PickleballPainter(color)),
    );
  }
}

class _PickleballPainter extends CustomPainter {
  final Color? tint;
  _PickleballPainter(this.tint);

  @override
  void paint(Canvas canvas, Size size) {
    // Natural multi-color illustration when no tint is requested; a single
    // flat color for every shape when one is (e.g. inside an accent chip).
    final paddlePaint = Paint()..color = tint ?? const Color(0xFF0F766E);
    final paddleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.04,
        size.height * 0.04,
        size.width * 0.62,
        size.width * 0.62,
      ),
      Radius.circular(size.width * 0.26),
    );
    canvas.drawRRect(paddleRect, paddlePaint);

    final handlePaint = Paint()..color = tint ?? const Color(0xFF374151);
    final handleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.30,
        size.height * 0.60,
        size.width * 0.14,
        size.height * 0.36,
      ),
      Radius.circular(size.width * 0.06),
    );
    canvas.drawRRect(handleRect, handlePaint);

    final ballPaint = Paint()..color = tint ?? const Color(0xFFCFE94A);
    final ballCenter = Offset(size.width * 0.80, size.height * 0.78);
    final ballRadius = size.width * 0.16;
    canvas.drawCircle(ballCenter, ballRadius, ballPaint);

    final holePaint = Paint()
      ..color = tint ?? const Color(0xFF5B6B0E);
    final holeOffsets = [
      Offset(
        ballCenter.dx - ballRadius * 0.4,
        ballCenter.dy - ballRadius * 0.3,
      ),
      Offset(
        ballCenter.dx + ballRadius * 0.3,
        ballCenter.dy - ballRadius * 0.2,
      ),
      Offset(ballCenter.dx, ballCenter.dy + ballRadius * 0.4),
    ];
    for (final o in holeOffsets) {
      canvas.drawCircle(o, ballRadius * 0.14, holePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PickleballPainter oldDelegate) =>
      oldDelegate.tint != tint;
}
