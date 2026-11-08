import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/inbody.dart';
import '../../data/entities.dart';
import '../../widgets/inbody_widgets.dart';
import '../../widgets/share_capture.dart';

/// 比較する項目。[better] は 1 なら増えると良い、-1 なら減ると良い、0 はどちらでもない
class _Row {
  const _Row(this.label, this.unit, this.of, {this.digits = 1, this.better = 0});

  final String label;
  final String unit;
  final double? Function(InBodyResult r) of;
  final int digits;
  final int better;
}

final _sections = <(String, List<_Row>)>[
  (
    '体成分',
    [
      _Row('体重', 'kg', (r) => r.weight.value),
      _Row('骨格筋量', 'kg', (r) => r.smm.value, better: 1),
      _Row('体脂肪量', 'kg', (r) => r.bfm.value, better: -1),
      _Row('体脂肪率', '%', (r) => r.pbf.value, better: -1),
      _Row('除脂肪量', 'kg', (r) => r.ffm, better: 1),
      _Row('体水分量', 'kg', (r) => r.tbw.value),
      _Row('タンパク質', 'kg', (r) => r.protein.value, better: 1),
      _Row('ミネラル', 'kg', (r) => r.mineral.value, digits: 2),
      _Row('BMI', '', (r) => r.bmi.value),
      _Row('InBody点数', '点', (r) => r.score.toDouble(), digits: 0, better: 1),
    ],
  ),
  (
    '部位別筋肉量',
    [
      _Row('右腕', 'kg', (r) => r.segmentLean.rightArm, digits: 2, better: 1),
      _Row('左腕', 'kg', (r) => r.segmentLean.leftArm, digits: 2, better: 1),
      _Row('体幹', 'kg', (r) => r.segmentLean.trunk, better: 1),
      _Row('右脚', 'kg', (r) => r.segmentLean.rightLeg, digits: 2, better: 1),
      _Row('左脚', 'kg', (r) => r.segmentLean.leftLeg, digits: 2, better: 1),
    ],
  ),
  (
    '部位別体脂肪量',
    [
      _Row('右腕', 'kg', (r) => r.segmentFat.rightArm, better: -1),
      _Row('左腕', 'kg', (r) => r.segmentFat.leftArm, better: -1),
      _Row('体幹', 'kg', (r) => r.segmentFat.trunk, better: -1),
      _Row('右脚', 'kg', (r) => r.segmentFat.rightLeg, better: -1),
      _Row('左脚', 'kg', (r) => r.segmentFat.leftLeg, better: -1),
    ],
  ),
  (
    '研究項目',
    [
      _Row('基礎代謝量', 'kcal', (r) => r.bmr.toDouble(), digits: 0, better: 1),
      _Row('内臓脂肪レベル', '', (r) => r.visceralLevel?.toDouble(), digits: 0, better: -1),
      _Row('ウエストヒップ比', '', (r) => r.whr.value, digits: 2, better: -1),
      _Row('腹囲', 'cm', (r) => r.waistCm, better: -1),
      _Row('推奨摂取量', 'kcal', (r) => r.recommendedKcal.toDouble(), digits: 0),
    ],
  ),
];

/// InBody の用紙 QR で取り込んだ2回の測定を並べて比べる（新しい順の [records]）
class InBodyCompareScreen extends StatefulWidget {
  const InBodyCompareScreen({super.key, required this.records});

  final List<InBodyRecord> records;

  @override
  State<InBodyCompareScreen> createState() => _InBodyCompareScreenState();
}

class _InBodyCompareScreenState extends State<InBodyCompareScreen> {
  late InBodyRecord _before = widget.records[1];
  late InBodyRecord _after = widget.records[0];
  final _cache = <String, InBodyResult?>{};
  final _shareKey = GlobalKey();

  InBodyResult? _parse(InBodyRecord r) => _cache.putIfAbsent(r.raw, () {
        try {
          return parseInBodyQr(r.raw);
        } on InBodyFormatException {
          return null;
        }
      });

  String _label(InBodyRecord r) => jpDate(parseYmd(r.date));

  void _share(InBodyResult a, InBodyResult b) {
    String d(double x, double y, int digits) {
      final v = y - x;
      return '${v >= 0 ? '+' : ''}${v.toStringAsFixed(digits)}';
    }

    final text = '${_label(_before)}→${_label(_after)}：'
        '体重${d(a.weight.value, b.weight.value, 1)}kg・'
        '骨格筋量${d(a.smm.value, b.smm.value, 1)}kg・'
        '体脂肪率${d(a.pbf.value, b.pbf.value, 1)}%';
    shareCapture(context, _shareKey, text: text, fileName: 'inbody_compare');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = _parse(_before);
    final b = _parse(_after);
    DropdownButton<InBodyRecord> picker(InBodyRecord value, ValueChanged<InBodyRecord> onChanged) =>
        DropdownButton<InBodyRecord>(
          value: value,
          isExpanded: true,
          items: [
            for (final r in widget.records) DropdownMenuItem(value: r, child: Text(_label(r))),
          ],
          onChanged: (v) {
            if (v != null) setState(() => onChanged(v));
          },
        );
    return Scaffold(
      appBar: AppBar(
        title: const Text('InBody の比較'),
        actions: [ShareButton(onPressed: a == null || b == null ? null : () => _share(a, b))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              Expanded(child: picker(_before, (v) => _before = v)),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward)),
              Expanded(child: picker(_after, (v) => _after = v)),
            ],
          ),
          const SizedBox(height: 8),
          if (a == null || b == null)
            const Text('この記録は読み取れませんでした')
          else
            ShareFrame(
              captureKey: _shareKey,
              child: Column(
                children: [
                  for (final (title, rows) in _sections)
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: theme.textTheme.labelLarge),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Expanded(flex: 4, child: SizedBox()),
                                Expanded(
                                  flex: 3,
                                  child: Text(_label(_before),
                                      textAlign: TextAlign.right, style: theme.textTheme.bodySmall),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(_label(_after),
                                      textAlign: TextAlign.right, style: theme.textTheme.bodySmall),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text('変化', textAlign: TextAlign.right, style: theme.textTheme.bodySmall),
                                ),
                              ],
                            ),
                            for (final row in rows) _rowWidget(context, row, a, b),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _rowWidget(BuildContext context, _Row row, InBodyResult a, InBodyResult b) {
    final x = row.of(a);
    final y = row.of(b);
    final diff = (x == null || y == null) ? null : y - x;
    Color? color;
    if (diff != null && row.better != 0 && diff.abs() >= 0.05) {
      color = (diff > 0) == (row.better > 0) ? levelStyle(context, 0).color : levelStyle(context, 1).color;
    }
    String f(double? v) => v == null ? '−' : v.toStringAsFixed(row.digits);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text(row.unit.isEmpty ? row.label : '${row.label}（${row.unit}）')),
          Expanded(flex: 3, child: Text(f(x), textAlign: TextAlign.right)),
          Expanded(
            flex: 3,
            child: Text(f(y), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              diff == null ? '' : '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(row.digits)}',
              textAlign: TextAlign.right,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
