import 'package:flutter/material.dart';

import '../core/forecast.dart';

String _kg(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}kg';

/// 体重の見込みカード
class ForecastCard extends StatelessWidget {
  const ForecastCard({super.key, required this.forecast, required this.currentKg, this.title = '体重の見込み'});

  final WeightForecast forecast;
  final double? currentKg;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = forecast;
    final after = currentKg == null ? null : currentKg! + f.kgPer30Days;
    final trendAfter = (currentKg == null || f.trendKgPer30Days == null) ? null : currentKg! + f.trendKgPer30Days!;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'このペースだと1か月後 '),
              TextSpan(
                text: after == null ? _kg(f.kgPer30Days) : '約${after.toStringAsFixed(1)}kg（${_kg(f.kgPer30Days)}）',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ])),
            const SizedBox(height: 4),
            Text(
              '1日平均：摂取 ${f.avgIntake.round()}kcal − 消費 ${f.avgBurn.round()}kcal ＝ '
              '${f.avgBalance >= 0 ? '+' : ''}${f.avgBalance.round()}kcal（${f.days}日分）',
              style: theme.textTheme.bodySmall,
            ),
            if (f.trendKgPer30Days != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '実際の体重の推移から：1か月で ${_kg(f.trendKgPer30Days!)}'
                  '${trendAfter == null ? '' : '（約${trendAfter.toStringAsFixed(1)}kg）'}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              '消費＝基礎代謝${f.bmr.round()}kcal${f.bmrEstimated ? '（体重からの目安）' : '（InBody）'}×1.1＋歩行・運動。'
              '体脂肪1kg＝7200kcal として計算した目安です。記録していない食事があると少なく見積もられます。',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
