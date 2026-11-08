import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 距離（km）を横軸にした折れ線グラフ（ペース・標高・心拍）
class SeriesChart extends StatelessWidget {
  const SeriesChart({
    super.key,
    required this.xs,
    required this.ys,
    required this.color,
    required this.format,
    this.invert = false,
    this.height = 140,
  });

  final List<double> xs;
  final List<double> ys;
  final Color color;

  /// 縦軸の値の表記
  final String Function(double) format;

  /// true なら小さい値を上に描く（ペースは速いほど上）
  final bool invert;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _SeriesPainter(
          xs: xs,
          ys: ys,
          color: color,
          format: format,
          invert: invert,
          grid: scheme.outlineVariant,
          text: scheme.onSurfaceVariant,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _SeriesPainter extends CustomPainter {
  _SeriesPainter({
    required this.xs,
    required this.ys,
    required this.color,
    required this.format,
    required this.invert,
    required this.grid,
    required this.text,
  });

  final List<double> xs;
  final List<double> ys;
  final Color color;
  final String Function(double) format;
  final bool invert;
  final Color grid;
  final Color text;

  void _label(Canvas c, String s, Offset at, {bool right = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: 10, color: text)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, right ? at - Offset(tp.width, 0) : at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (xs.length < 2 || ys.length != xs.length) return;
    const left = 40.0, bottom = 16.0, top = 6.0;
    final w = size.width - left;
    final h = size.height - bottom - top;
    var minY = ys.reduce(math.min);
    var maxY = ys.reduce(math.max);
    if (maxY - minY < 1e-6) {
      minY -= 1;
      maxY += 1;
    }
    final pad = (maxY - minY) * 0.08;
    minY -= pad;
    maxY += pad;
    final minX = xs.first, maxX = xs.last <= xs.first ? xs.first + 1 : xs.last;
    double px(double x) => left + (x - minX) / (maxX - minX) * w;
    double py(double y) {
      final f = (y - minY) / (maxY - minY);
      return top + (invert ? f : 1 - f) * h;
    }

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 0.5;
    for (var i = 0; i <= 2; i++) {
      final y = top + h * i / 2;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), gridPaint);
      final v = invert ? minY + (maxY - minY) * i / 2 : maxY - (maxY - minY) * i / 2;
      _label(canvas, format(v), Offset(left - 4, y - 6), right: true);
    }
    // 横軸：km
    final kmStep = math.max(1, ((maxX - minX) / 5).ceil());
    for (var k = (minX / kmStep).ceil() * kmStep; k <= maxX; k += kmStep) {
      _label(canvas, '${k}km', Offset(px(k.toDouble()) - 8, size.height - bottom + 2));
    }

    final path = Path()..moveTo(px(xs.first), py(ys.first));
    for (var i = 1; i < xs.length; i++) {
      path.lineTo(px(xs[i]), py(ys[i]));
    }
    final fill = Path.from(path)
      ..lineTo(px(xs.last), top + h)
      ..lineTo(px(xs.first), top + h)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.15));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SeriesPainter old) => old.xs != xs || old.ys != ys || old.color != color;
}

/// 期間ごとの棒グラフ（運動の時間・距離など）
class PeriodBarChart extends StatelessWidget {
  const PeriodBarChart({
    super.key,
    required this.labels,
    required this.values,
    required this.format,
    this.highlightLast = true,
  });

  final List<String> labels;
  final List<double> values;
  final String Function(double) format;
  final bool highlightLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxV = values.fold<double>(0, math.max);
    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FittedBox(
                      child: Text(values[i] <= 0 ? '' : format(values[i]), style: const TextStyle(fontSize: 9)),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      height: maxV <= 0 ? 0 : 92 * values[i] / maxV,
                      decoration: BoxDecoration(
                        color: highlightLast && i == values.length - 1
                            ? scheme.primary
                            : scheme.primary.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(child: Text(labels[i], style: const TextStyle(fontSize: 10))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
