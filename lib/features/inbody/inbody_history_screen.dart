import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/activity.dart';
import '../../core/dates.dart';
import '../../core/inbody.dart';
import '../../data/entities.dart';
import '../../services/health_service.dart';
import '../../widgets/inbody_widgets.dart';
import '../../widgets/weight_chart.dart';
import '../history/history_common.dart';
import 'inbody_result_screen.dart';
import 'inbody_scan_screen.dart';

enum _Metric {
  weight('体重', 'kg'),
  pbf('体脂肪率', '%'),
  bfm('体脂肪量', 'kg'),
  lean('除脂肪量', 'kg'),
  smm('骨格筋量', 'kg');

  const _Metric(this.label, this.unit);
  final String label;
  final String unit;
}

/// 1日分の体組成（QRで取り込んだ InBody の結果と、ヘルスコネクトの値をまとめたもの）
class _BodyDay {
  _BodyDay(this.date);

  final String date;
  double? weight;
  double? pbf;
  double? lean;
  double? smm;
  int? score;

  /// QRで取り込んだ結果（あれば詳細を開ける）
  InBodyRecord? record;
  final Set<String> sources = {};

  double? get bfm {
    if (record != null) return record!.bfmKg;
    if (weight != null && pbf != null) return weight! * pbf! / 100;
    if (weight != null && lean != null) return weight! - lean!;
    return null;
  }

  double? leanOrDerived() => lean ?? (weight != null && bfm != null ? weight! - bfm! : null);

  double? value(_Metric m) => switch (m) {
        _Metric.weight => weight,
        _Metric.pbf => pbf,
        _Metric.bfm => bfm,
        _Metric.lean => leanOrDerived(),
        _Metric.smm => smm,
      };
}

/// 体組成の記録（InBody の用紙 QR ＋ ヘルスコネクトの体重・体脂肪・除脂肪量）
class InBodyHistoryScreen extends StatefulWidget {
  const InBodyHistoryScreen({super.key});

  @override
  State<InBodyHistoryScreen> createState() => _InBodyHistoryScreenState();
}

class _InBodyHistoryScreenState extends State<InBodyHistoryScreen> {
  List<_BodyDay>? _days;
  _Metric _metric = _Metric.weight;
  HistoryPeriod _period = HistoryPeriod.year;
  Set<String> _granted = {};
  String? _error;

  AppServices get s => AppServices.I;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final now = DateTime.now();
    final from = _period.from(now);
    final fromDay = ymd(from);
    final byDate = <String, _BodyDay>{};
    _BodyDay day(String d) => byDate.putIfAbsent(d, () => _BodyDay(d));

    var granted = <String>{};
    if (s.settings.healthEnabled) {
      try {
        granted = await s.health.granted();
        final body = await s.health.readBody(from, now);
        // 同じ日に複数あれば、その日の一番遅い値を使う
        void put(List<HealthSample> list, void Function(_BodyDay d, double v) set) {
          final sorted = [...list]..sort((a, b) => a.time.compareTo(b.time));
          for (final x in sorted) {
            final d = day(ymd(x.time));
            set(d, x.value);
            d.sources.add(originLabel(x.origin));
          }
        }

        put(body.weight, (d, v) => d.weight = v);
        put(body.bodyFat, (d, v) => d.pbf = v);
        put(body.leanMass, (d, v) => d.lean = v);
      } catch (e) {
        _error = '$e';
      }
    }

    // QRで取り込んだ結果は詳しいので、同じ日ならこちらを優先
    final records = await s.db.inbodyResults();
    for (final r in records.reversed) {
      if (r.date.compareTo(fromDay) < 0) continue;
      final d = day(r.date);
      d.record = r;
      d.weight = r.weightKg;
      d.pbf = r.pbf;
      d.smm = r.smmKg;
      d.score = r.score;
      d.lean = r.weightKg - r.bfmKg;
      d.sources.add('InBody用紙');
    }

    final list = byDate.values.toList()..sort((a, b) => b.date.compareTo(a.date));
    if (!mounted) return;
    setState(() {
      _granted = granted;
      _days = list;
    });
  }

  Future<void> _scan() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InBodyScanScreen()));
    await _load();
  }

  Future<void> _requestMore() async {
    try {
      await s.health.request();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('許可画面を開けませんでした：$e')));
    }
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
    final days = _days;
    return Scaffold(
      appBar: AppBar(title: const Text('体組成の記録')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scan,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('InBodyのQR'),
      ),
      body: days == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _list(context, days)),
    );
  }

  Widget _list(BuildContext context, List<_BodyDay> days) {
    final theme = Theme.of(context);
    final healthOn = s.settings.healthEnabled;

    // グラフ用：古い順
    final points = days.reversed
        .where((d) => d.value(_metric) != null)
        .map((d) => WeightEntry(date: d.date, kg: d.value(_metric)!))
        .toList();
    final from = points.isEmpty ? dayOnly(DateTime.now()) : parseYmd(points.first.date);
    final to = points.length < 2 ? addDays(from, 7) : parseYmd(points.last.date);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        PeriodSelector(value: _period, onChanged: (p) {
          setState(() => _period = p);
          _load();
        }),
        const SizedBox(height: 8),
        if (!healthOn)
          const InfoCard(
            text: 'ヘルスコネクトと連携すると、InBody アプリが記録した体重・体脂肪率もここに表示されます（設定 → ヘルスコネクト）。'
                '下のボタンからは、結果用紙の QR を取り込めます。',
          )
        else if (!_granted.contains('history'))
          MorePermissionCard(missing: const ['30日より前の記録'], onRequest: _requestMore),
        if (_error != null) InfoCard(text: 'ヘルスコネクトの読み取りでエラーが起きました：$_error'),
        if (days.isEmpty)
          const InfoCard(text: 'この期間の記録はありません。')
        else ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_Metric>(
              showSelectedIcon: false,
              segments: [for (final m in _Metric.values) ButtonSegment(value: m, label: Text(m.label))],
              selected: {_metric},
              onSelectionChanged: (sel) => setState(() => _metric = sel.first),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: points.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _metric == _Metric.smm ? '骨格筋量は InBody の用紙 QR から取り込んだ分だけ表示できます' : 'この項目の記録がありません',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : WeightChart(entries: points, from: from, to: to),
            ),
          ),
          if (points.length >= 2)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${shortDate(parseYmd(points.first.date))}からの変化：'
                '${signed1(points.last.kg - points.first.kg)} ${_metric.unit}',
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 16),
          Text('測定結果', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          for (final d in days) _tile(context, d),
        ],
      ],
    );
  }

  Widget _tile(BuildContext context, _BodyDay d) {
    String f(double? v, String unit) => v == null ? '' : '${v.toStringAsFixed(1)}$unit';
    final parts = [
      if (d.weight != null) '体重 ${f(d.weight, 'kg')}',
      if (d.pbf != null) '体脂肪率 ${f(d.pbf, '%')}',
      if (d.smm != null) '骨格筋 ${f(d.smm, 'kg')}' else if (d.leanOrDerived() != null) '除脂肪 ${f(d.leanOrDerived(), 'kg')}',
    ];
    final rec = d.record;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: rec == null ? null : () => _open(rec),
        leading: rec != null
            ? CircleAvatar(child: Text('${d.score ?? ''}'))
            : const CircleAvatar(child: Icon(Icons.monitor_weight_outlined, size: 20)),
        title: Text('${jpDate(parseYmd(d.date))}　${d.sources.join('・')}'),
        subtitle: Text(parts.join('・')),
        trailing: rec != null ? const Icon(Icons.chevron_right) : null,
      ),
    );
  }
}
