// rating_sparkline.dart
// A tiny inline rating-history trend line, fetched from the backend's
// GET /sports/user/:userId/rating-history?sport=&format= endpoint. There's
// no axis/label chrome by design — this sits next to a player's current
// rating number just to show the recent direction (up/down), not to be a
// full chart in its own right.
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../main.dart';
import '../api_client.dart';

class RatingSparkline extends StatefulWidget {
  final int userId;
  final String sport;
  final String format;
  final double width;
  final double height;

  const RatingSparkline({
    super.key,
    required this.userId,
    required this.sport,
    required this.format,
    this.width = 80,
    this.height = 32,
  });

  @override
  State<RatingSparkline> createState() => _RatingSparklineState();
}

class _RatingSparklineState extends State<RatingSparkline> {
  List<double>? _points;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiClient.get(
        '/sports/user/${widget.userId}/rating-history',
        queryParams: {'sport': widget.sport, 'format': widget.format},
      );
      if (res.statusCode == 200 && mounted) {
        final history = res.data['history'] as List;
        setState(() {
          _points = history
              .map<double>((h) => (h['rating'] as num).toDouble())
              .toList();
        });
      }
    } catch (err) {
      // Best-effort — a missing sparkline shouldn't block the rest of the
      // profile from showing.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = _points;
    // Not enough history yet for a meaningful trend line (brand-new player,
    // or still loading) — reserve the space so the row's layout doesn't jump.
    if (_loading || points == null || points.length < 2) {
      return SizedBox(width: widget.width, height: widget.height);
    }

    final trendingUp = points.last >= points.first;
    final color = trendingUp ? AppColors.success : AppColors.danger;

    final minY = points.reduce((a, b) => a < b ? a : b);
    final maxY = points.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY) * 0.1 + 0.5; // avoid a degenerate flat scale

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: LineChart(
        LineChartData(
          minY: minY - pad,
          maxY: maxY + pad,
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (int i = 0; i < points.length; i++)
                  FlSpot(i.toDouble(), points[i]),
              ],
              isCurved: true,
              color: color,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
