import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/meal_type.dart';
import '../core/theme.dart';

/// ホームの量り表示：液晶の数字で「のこり kcal」、その下に食事区分ごとの帯グラフ。
/// 帯は 朝→昼→夕→間食 の順に積み上がり、残りは空き（目盛りだけ）の区画。超えた分は赤で目標線の先に伸びる
class ScaleDisplay extends StatelessWidget {
  const ScaleDisplay({
    super.key,
    required this.byType,
    required this.target,
    this.baseTarget,
    this.burn = 0,
  });

  /// 食事区分ごとの摂取 kcal
  final Map<MealType, double> byType;

  /// 目標（消費の上乗せ込み）
  final double target;

  /// 上乗せ前の目標（上乗せがあるときだけ表示）
  final double? baseTarget;
  final double burn;

  double get total => byType.values.fold(0.0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final remain = target - total;
    final over = remain < 0;
    const sub = TextStyle(fontSize: 12, color: AppColors.lcdSub);
    return Semantics(
      label: over ? '目標を ${kcal0(-remain)} kcal 超えています' : 'のこり ${kcal0(remain)} kcal',
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.lcd,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.text, width: 2),
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(over ? 'オーバー' : 'のこり', style: sub.copyWith(color: over ? AppColors.error : AppColors.lcdSub)),
                const Spacer(),
                Text(
                  burn > 0 ? '目標 ${kcal0(baseTarget ?? target)}＋消費 ${kcal0(burn)}' : '目標 ${kcal0(target)}',
                  style: sub,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  kcal0(remain.abs()),
                  style: lcdNumberStyle.copyWith(fontSize: 52, color: over ? AppColors.error : AppColors.lcdInk),
                ),
                const SizedBox(width: 4),
                Text('kcal', style: lcdNumberStyle.copyWith(fontSize: 16)),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 22,
              child: CustomPaint(painter: _BandPainter(byType: byType, target: target)),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 2,
              children: [
                for (final t in MealType.values)
                  _Legend(
                    color: _shade(t),
                    text: '${t.label} ${(byType[t] ?? 0) > 0 ? kcal0(byType[t]!) : '—'}',
                  ),
                _Legend(color: null, text: over ? '超過 ${kcal0(-remain)}' : 'のこり ${kcal0(remain)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 区分ごとの墨の濃さ（色数を増やさず濃淡で分ける）
Color _shade(MealType t) => switch (t) {
      MealType.breakfast => AppColors.lcdInk,
      MealType.lunch => AppColors.lcdInk.withAlpha(195),
      MealType.dinner => AppColors.lcdInk.withAlpha(140),
      MealType.snack => AppColors.lcdInk.withAlpha(90),
    };

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});

  final Color? color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            border: color == null ? Border.all(color: AppColors.lcdInk) : null,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.lcdInk,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _BandPainter extends CustomPainter {
  _BandPainter({required this.byType, required this.target});

  final Map<MealType, double> byType;
  final double target;

  @override
  void paint(Canvas canvas, Size size) {
    final total = byType.values.fold(0.0, (a, b) => a + b);
    final scale = [target, total, 1.0].reduce((a, b) => a > b ? a : b);
    final w = size.width;
    final h = size.height;
    final ink = Paint()
      ..color = AppColors.lcdInk
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // 目盛り（目標までを10等分）
    final targetX = w * target / scale;
    for (var i = 1; i < 10; i++) {
      final x = targetX * i / 10;
      final th = i == 5 ? h * 0.6 : h * 0.3;
      canvas.drawLine(Offset(x, h - th), Offset(x, h), ink..color = AppColors.lcdInk.withAlpha(110));
    }

    // 区分ごとの積み上げ
    var x = 0.0;
    for (final t in MealType.values) {
      final v = byType[t] ?? 0;
      if (v <= 0) continue;
      final segW = w * v / scale;
      canvas.drawRect(Rect.fromLTWH(x, 0, segW, h), Paint()..color = _shade(t));
      // 区切り（液晶の色の細線）
      if (x > 0) {
        canvas.drawLine(Offset(x, 0), Offset(x, h), Paint()
          ..color = AppColors.lcd
          ..strokeWidth = 1.5);
      }
      x += segW;
    }

    // 目標を超えた分は赤く重ねる
    if (total > target) {
      canvas.drawRect(Rect.fromLTWH(targetX, 0, w - targetX, h), Paint()..color = AppColors.error.withAlpha(200));
      canvas.drawLine(Offset(targetX, -3), Offset(targetX, h + 3), Paint()
        ..color = AppColors.text
        ..strokeWidth = 2);
    }

    // 枠
    canvas.drawRect(Rect.fromLTWH(0.5, 0.5, w - 1, h - 1), ink..color = AppColors.lcdInk);
  }

  @override
  bool shouldRepaint(covariant _BandPainter old) => old.target != target || old.byType != byType;
}
