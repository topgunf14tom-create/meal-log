import 'package:flutter/material.dart';

/// 履歴画面の表示期間
enum HistoryPeriod {
  threeMonths('3か月'),
  year('1年'),
  all('すべて');

  const HistoryPeriod(this.label);
  final String label;

  DateTime from(DateTime now) => switch (this) {
        HistoryPeriod.threeMonths => DateTime(now.year, now.month - 3, now.day),
        HistoryPeriod.year => DateTime(now.year - 1, now.month, now.day),
        HistoryPeriod.all => DateTime(2010),
      };
}

class PeriodSelector extends StatelessWidget {
  const PeriodSelector({super.key, required this.value, required this.onChanged});

  final HistoryPeriod value;
  final ValueChanged<HistoryPeriod> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<HistoryPeriod>(
        showSelectedIcon: false,
        segments: [for (final p in HistoryPeriod.values) ButtonSegment(value: p, label: Text(p.label))],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      );
}

class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
}

/// 追加の権限（過去のデータ・距離など）を求めるカード
class MorePermissionCard extends StatelessWidget {
  const MorePermissionCard({super.key, required this.missing, required this.onRequest});

  final List<String> missing;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${missing.join('・')}を読むには、ヘルスコネクトで追加の許可が必要です。'
                  '許可画面で「過去のデータ」などをオンにしてください。'),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: onRequest, child: const Text('許可する')),
              ),
            ],
          ),
        ),
      );
}
