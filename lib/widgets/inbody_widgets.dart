import 'package:flutter/material.dart';

import '../core/inbody.dart';

/// 標準範囲の判定ラベルと色
({String label, Color color}) levelStyle(BuildContext context, int? level) {
  final scheme = Theme.of(context).colorScheme;
  switch (level) {
    case -1:
      return (label: '低い', color: const Color(0xFF1E88E5));
    case 1:
      return (label: '高い', color: const Color(0xFFE53935));
    case 0:
      return (label: '標準', color: const Color(0xFF2E7D5B));
    default:
      return (label: '', color: scheme.onSurfaceVariant);
  }
}

/// 小数1桁の符号つき（+1.2 / -0.4 / 0.0）
String signed1(double v) {
  final r = double.parse(v.toStringAsFixed(1));
  if (r == 0) return '0.0';
  return '${r > 0 ? '+' : ''}${r.toStringAsFixed(1)}';
}

class InBodySection extends StatelessWidget {
  const InBodySection({super.key, required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                if (subtitle != null) ...[
                  const SizedBox(width: 8),
                  Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// 標準範囲の帯つき横棒グラフ（InBody の「筋肉・脂肪分析」「肥満分析」風）
class InBodyRangeBar extends StatelessWidget {
  const InBodyRangeBar({
    super.key,
    required this.label,
    required this.valueText,
    required this.position,
    required this.min,
    required this.max,
    required this.normalLow,
    required this.normalHigh,
    this.ticks = const [],
  });

  final String label;
  final String valueText;

  /// 棒の長さを決める値（% や BMI など、目盛りと同じ単位）
  final double position;
  final double min;
  final double max;
  final double normalLow;
  final double normalHigh;
  final List<double> ticks;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final level = position < normalLow ? -1 : (position > normalHigh ? 1 : 0);
    final color = levelStyle(context, level).color;
    double frac(double v) => ((v - min) / (max - min)).clamp(0.0, 1.0).toDouble();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 64, child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final w = c.maxWidth;
              return SizedBox(
                height: 34,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 標準範囲の帯
                    Positioned(
                      left: frac(normalLow) * w,
                      width: (frac(normalHigh) - frac(normalLow)) * w,
                      top: 0,
                      height: 20,
                      child: Container(color: scheme.primaryContainer.withValues(alpha: 0.6)),
                    ),
                    // 値
                    Positioned(
                      left: 0,
                      top: 5,
                      height: 10,
                      width: frac(position) * w,
                      child: Container(
                        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 20,
                      height: 1,
                      child: Container(color: scheme.outlineVariant),
                    ),
                    for (final t in ticks)
                      Positioned(
                        left: frac(t) * w - 16,
                        width: 32,
                        top: 21,
                        child: Text(
                          t == t.roundToDouble() ? t.toInt().toString() : t.toString(),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
          SizedBox(
            width: 64,
            child: Text(
              valueText,
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// 部位別（右腕・左腕・体幹・右脚・左脚）を人の形に並べる
class InBodySegmentFigure extends StatelessWidget {
  const InBodySegmentFigure({super.key, required this.segments, this.unit = 'kg', this.digits});

  final InBodySegments segments;
  final String unit;

  /// 部位ごとの小数桁（未指定なら腕脚2桁・体幹1桁）
  final List<int>? digits;

  @override
  Widget build(BuildContext context) {
    final d = digits ?? const [2, 2, 1, 2, 2];
    final v = segments.values;
    Widget cell(String name, int i) => _SegmentCell(name: name, value: '${v[i].toStringAsFixed(d[i])} $unit');
    return Column(
      children: [
        Row(children: [Expanded(child: cell('右腕', 0)), const SizedBox(width: 8), Expanded(child: cell('左腕', 1))]),
        const SizedBox(height: 8),
        Row(children: [const Spacer(), Expanded(flex: 2, child: cell('体幹', 2)), const Spacer()]),
        const SizedBox(height: 8),
        Row(children: [Expanded(child: cell('右脚', 3)), const SizedBox(width: 8), Expanded(child: cell('左脚', 4))]),
      ],
    );
  }
}

class _SegmentCell extends StatelessWidget {
  const _SegmentCell({required this.name, required this.value});

  final String name;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(name, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// 主要項目のタイル（値＋前回比）
class InBodyStatTile extends StatelessWidget {
  const InBodyStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    this.diff,
    this.level,
  });

  final String label;
  final String value;
  final String unit;
  final double? diff;
  final int? level;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = levelStyle(context, level);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              TextSpan(text: ' $unit', style: theme.textTheme.bodySmall),
            ]),
          ),
          if (style.label.isNotEmpty)
            Text(style.label, style: TextStyle(fontSize: 12, color: style.color, fontWeight: FontWeight.bold)),
          if (diff != null)
            Text(
              '前回比 ${signed1(diff!)}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// 「名前・値・標準範囲・判定」の1行
class InBodyValueRow extends StatelessWidget {
  const InBodyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.unit = '',
    this.range,
    this.level,
    this.bold = false,
  });

  final String label;
  final String value;
  final String unit;
  final String? range;
  final int? level;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = levelStyle(context, level);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : null)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              unit.isEmpty ? value : '$value $unit',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              range ?? '',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              style.label,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: style.color, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
