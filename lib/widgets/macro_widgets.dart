import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';

/// 実績 g と目標 g の横棒
class MacroBar extends StatelessWidget {
  const MacroBar({super.key, required this.label, required this.value, required this.target, required this.color});

  final String label;
  final double value;
  final double target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ratio = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0).toDouble();
    final over = target > 0 && value > target * 1.1;
    final errorColor = Theme.of(context).colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('${g1(value)} / ${g1(target)} g', style: TextStyle(color: over ? errorColor : null)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            color: over ? errorColor : color,
            backgroundColor: color.withAlpha(50),
          ),
        ),
      ],
    );
  }
}

/// PFC エネルギー比率のドーナツグラフ
class PfcPie extends StatelessWidget {
  const PfcPie({super.key, required this.p, required this.f, required this.c, this.size = 96});

  final double p;
  final double f;
  final double c;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PiePainter(p, f, c, Theme.of(context).colorScheme.surfaceContainerHighest),
      ),
    );
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.p, this.f, this.c, this.empty);

  final double p;
  final double f;
  final double c;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final total = p + f + c;
    if (total <= 0) {
      canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = empty);
      return;
    }
    var start = -math.pi / 2;
    final parts = <(double, Color)>[
      (p, MacroColors.protein),
      (f, MacroColors.fat),
      (c, MacroColors.carbs),
    ];
    for (final (v, color) in parts) {
      final sweep = math.pi * 2 * v / total;
      canvas.drawArc(rect, start, sweep, false, paint..color = color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) =>
      oldDelegate.p != p || oldDelegate.f != f || oldDelegate.c != c;
}

/// 信頼度・情報源の小さなラベル
class InfoChip extends StatelessWidget {
  const InfoChip(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withAlpha(120)),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: c)),
    );
  }
}

String confidenceLabel(String c) => switch (c) {
      'high' => '信頼度 高',
      'low' => '信頼度 低',
      _ => '信頼度 中',
    };

String sourceLabel(String s) => switch (s) {
      'official' => '公式データ',
      'reference' => '参考データ',
      'manual' => '手入力',
      _ => '写真から推定',
    };
