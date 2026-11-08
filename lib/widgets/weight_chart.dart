import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../data/entities.dart';

/// 体重の折れ線グラフ
class WeightChart extends StatelessWidget {
  const WeightChart({super.key, required this.entries, required this.from, required this.to});

  final List<WeightEntry> entries;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 220,
      width: double.infinity,
      child: CustomPaint(
        painter: _WeightPainter(
          entries: entries,
          from: from,
          to: to,
          line: scheme.primary,
          grid: scheme.outlineVariant,
          text: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _WeightPainter extends CustomPainter {
  _WeightPainter({
    required this.entries,
    required this.from,
    required this.to,
    required this.line,
    required this.grid,
    required this.text,
  });

  final List<WeightEntry> entries;
  final DateTime from;
  final DateTime to;
  final Color line;
  final Color grid;
  final Color text;

  void _label(Canvas canvas, String s, Offset at, {bool alignRight = false, bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: 11, color: text)),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (alignRight) dx -= tp.width;
    if (center) dx -= tp.width / 2;
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const left = 44.0, right = 12.0, top = 10.0, bottom = 24.0;
    final w = size.width - left - right;
    final h = size.height - top - bottom;

    if (entries.isEmpty) {
      _label(canvas, 'データがありません', Offset(size.width / 2, size.height / 2), center: true);
      return;
    }

    var minY = entries.map((e) => e.kg).reduce(math.min);
    var maxY = entries.map((e) => e.kg).reduce(math.max);
    minY = (minY - 0.5).floorToDouble();
    maxY = (maxY + 0.5).ceilToDouble();
    if (maxY - minY < 1) maxY = minY + 1;

    final spanHours = math.max(1, to.difference(from).inHours).toDouble();
    double x(DateTime d) => left + (d.difference(from).inHours / spanHours).clamp(0.0, 1.0).toDouble() * w;
    double y(double v) => top + (1 - (v - minY) / (maxY - minY)) * h;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final v = minY + (maxY - minY) * i / 3;
      final yy = y(v);
      canvas.drawLine(Offset(left, yy), Offset(left + w, yy), gridPaint);
      _label(canvas, v.toStringAsFixed(1), Offset(left - 6, yy), alignRight: true);
    }
    _label(canvas, shortDate(from), Offset(left, top + h + 12));
    _label(canvas, shortDate(to), Offset(left + w, top + h + 12), alignRight: true);

    final path = Path();
    final dot = Paint()..color = line;
    for (var i = 0; i < entries.length; i++) {
      final pt = Offset(x(parseYmd(entries[i].date)), y(entries[i].kg));
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawCircle(pt, 3, dot);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
