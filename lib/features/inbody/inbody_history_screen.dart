import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/dates.dart';
import '../../core/inbody.dart';
import '../../data/entities.dart';
import '../../widgets/inbody_widgets.dart';
import '../../widgets/weight_chart.dart';
import 'inbody_result_screen.dart';
import 'inbody_scan_screen.dart';

enum _Metric {
  weight('体重', 'kg'),
  smm('骨格筋量', 'kg'),
  pbf('体脂肪率', '%'),
  bfm('体脂肪量', 'kg');

  const _Metric(this.label, this.unit);
  final String label;
  final String unit;

  double of(InBodyRecord r) => switch (this) {
        _Metric.weight => r.weightKg,
        _Metric.smm => r.smmKg,
        _Metric.pbf => r.pbf,
        _Metric.bfm => r.bfmKg,
      };
}

/// InBody の履歴（推移グラフと一覧）
class InBodyHistoryScreen extends StatefulWidget {
  const InBodyHistoryScreen({super.key});

  @override
  State<InBodyHistoryScreen> createState() => _InBodyHistoryScreenState();
}

class _InBodyHistoryScreenState extends State<InBodyHistoryScreen> {
  List<InBodyRecord>? _records;
  _Metric _metric = _Metric.weight;

  AppServices get s => AppServices.I;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await s.db.inbodyResults();
    if (mounted) setState(() => _records = list);
  }

  Future<void> _scan() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InBodyScanScreen()));
    await _load();
  }

  Future<void> _open(InBodyRecord rec) async {
    final InBodyResult result;
    try {
      result = parseInBodyQr(rec.raw);
    } on InBodyFormatException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => InBodyResultScreen(result: result, record: rec)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final records = _records;
    return Scaffold(
      appBar: AppBar(title: const Text('InBody')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scan,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('QRを読み取る'),
      ),
      body: records == null
          ? const Center(child: CircularProgressIndicator())
          : records.isEmpty
              ? _empty(context)
              : _list(context, records),
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'InBody の結果用紙の QR コードを読み取ると、\n体組成の結果と推移をここで見られます。\n\n'
            '読み取った体重は体重記録にも反映できます。\n（対応機種：InBody270）',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );

  Widget _list(BuildContext context, List<InBodyRecord> records) {
    final theme = Theme.of(context);
    // グラフ用：古い順。同じ日は最後の1件
    final byDate = <String, InBodyRecord>{};
    for (final r in records.reversed) {
      byDate[r.date] = r;
    }
    final points = byDate.values
        .map((r) => WeightEntry(date: r.date, kg: _metric.of(r)))
        .toList();
    final today = dayOnly(DateTime.now());
    final from = points.isEmpty ? today : parseYmd(points.first.date);
    final to = points.length < 2 ? addDays(from, 7) : parseYmd(points.last.date);
    final first = byDate.values.first;
    final last = byDate.values.last;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        SegmentedButton<_Metric>(
          showSelectedIcon: false,
          segments: [for (final m in _Metric.values) ButtonSegment(value: m, label: Text(m.label))],
          selected: {_metric},
          onSelectionChanged: (sel) => setState(() => _metric = sel.first),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: WeightChart(entries: points, from: from, to: to),
          ),
        ),
        if (points.length >= 2)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${shortDate(parseYmd(first.date))}からの変化：'
              '${signed1(_metric.of(last) - _metric.of(first))} ${_metric.unit}',
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(height: 16),
        Text('測定結果', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        for (final r in records)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              onTap: () => _open(r),
              leading: CircleAvatar(child: Text('${r.score}')),
              title: Text(jpDate(parseYmd(r.date))),
              subtitle: Text(
                '体重 ${r.weightKg.toStringAsFixed(1)}kg・骨格筋 ${r.smmKg.toStringAsFixed(1)}kg・'
                '体脂肪率 ${r.pbf.toStringAsFixed(1)}%',
              ),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
      ],
    );
  }
}
