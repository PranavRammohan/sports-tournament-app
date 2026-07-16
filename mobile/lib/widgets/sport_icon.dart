// sport_icon.dart
// Shared helper for showing a sport's icon consistently across the app.
// Badminton/Tennis/Table Tennis use emoji (they render fine).
// Pickleball has no standard emoji yet, so we draw a simple original icon.
import 'package:flutter/material.dart';

const Map<String, String> _sportEmojis = {
  'badminton': '🏸',
  'tennis': '🎾',
  'table_tennis': '🏓',
};

Widget sportIcon(String sportKey, {double size = 20, Color? color}) {
  final key = sportKey.toLowerCase().replaceAll(' ', '_');
  if (key == 'pickleball') {
    return PickleballIcon(size: size);
  }
  return Text(_sportEmojis[key] ?? '🏅', style: TextStyle(fontSize: size));
}

class PickleballIcon extends StatelessWidget {
  final double size;

  const PickleballIcon({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PickleballPainter()),
    );
  }
}

class _PickleballPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Paddle face — teal
    final paddlePaint = Paint()..color = const Color(0xFF0F766E);
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

    // Handle — dark gray
    final handlePaint = Paint()..color = const Color(0xFF374151);
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

    // Ball — yellow-green, like a real pickleball
    final ballPaint = Paint()..color = const Color(0xFFCFE94A);
    final ballCenter = Offset(size.width * 0.80, size.height * 0.78);
    final ballRadius = size.width * 0.16;
    canvas.drawCircle(ballCenter, ballRadius, ballPaint);

    // Ball holes/dimples — darker olive dots
    final holePaint = Paint()..color = const Color(0xFF5B6B0E);
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
