import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';

/// 実績 g と目標 g：量りの目盛り（目標までを10等分）の上に実績の太線
class MacroBar extends StatelessWidget {
  const MacroBar({super.key, required this.label, required this.value, required this.target, required this.color});

  final String label;
  final double value;
  final double target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final over = target > 0 && value > target * 1.1;
    final sub = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            const Spacer(),
            Text(
              '${g1(value)} / ${g1(target)} g',
              style: (sub ?? const TextStyle()).copyWith(
                color: over ? AppColors.over : AppColors.sub,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 12,
          width: double.infinity,
          child: CustomPaint(painter: _RulerPainter(target <= 0 ? 0 : value / target, over ? AppColors.over : color)),
        ),
      ],
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter(this.ratio, this.color);

  /// 実績 ÷ 目標（1 を超えたら右端で止める）
  final double ratio;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = AppColors.text
      ..strokeWidth = 1;
    final base = size.height - 0.5;
    canvas.drawLine(Offset(0, base), Offset(size.width, base), ink);
    for (var i = 0; i <= 10; i++) {
      final x = (size.width - 1) * i / 10 + 0.5;
      final h = i % 5 == 0 ? size.height : size.height * 0.5;
      canvas.drawLine(Offset(x, base - h), Offset(x, base), ink);
    }
    final w = size.width * ratio.clamp(0.0, 1.0);
    canvas.drawRect(Rect.fromLTWH(0, base - 5, w, 5), Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) => old.ratio != ratio || old.color != color;
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
        color: c.withAlpha(22),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withAlpha(110)),
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
