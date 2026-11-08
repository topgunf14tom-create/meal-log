import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/activity.dart';
import '../../core/dates.dart';
import '../../core/inbody.dart';
import '../../data/entities.dart';
import '../../services/health_service.dart';
import '../../widgets/inbody_widgets.dart';
import '../../widgets/share_capture.dart';
import '../../widgets/weight_chart.dart';
import '../history/history_common.dart';
import 'inbody_compare_screen.dart';
import 'inbody_result_screen.dart';
import 'inbody_scan_screen.dart';

/// グラフに出せる項目
class _Metric {
  const _Metric(this.label, this.unit, this.of, {this.qrOnly = false, this.digits = 1});

  final String label;
  final String unit;
  final double? Function(_BodyDay d) of;

  /// InBody の用紙 QR から取り込んだ日だけ値がある
  final bool qrOnly;
  final int digits;
}

double? _qr(_BodyDay d, double Function(InBodyResult r) f) => d.result == null ? null : f(d.result!);

final _basicMetrics = <_Metric>[
  _Metric('体重', 'kg', (d) => d.weight),
  _Metric('体脂肪率', '%', (d) => d.pbf),
  _Metric('体脂肪量', 'kg', (d) => d.bfm),
  _Metric('除脂肪量', 'kg', (d) => d.leanOrDerived()),
  _Metric('骨格筋量', 'kg', (d) => d.smm, qrOnly: true),
];

final _detailMetrics = <_Metric>[
  _Metric('InBody点数', '点', (d) => d.score?.toDouble(), qrOnly: true, digits: 0),
  _Metric('BMI', '', (d) => _qr(d, (r) => r.bmi.value), qrOnly: true),
  _Metric('体水分量', 'kg', (d) => _qr(d, (r) => r.tbw.value), qrOnly: true),
  _Metric('タンパク質', 'kg', (d) => _qr(d, (r) => r.protein.value), qrOnly: true),
  _Metric('基礎代謝量', 'kcal', (d) => _qr(d, (r) => r.bmr.toDouble()), qrOnly: true, digits: 0),
  _Metric('内臓脂肪レベル', '', (d) => _qr(d, (r) => (r.visceralLevel ?? 0).toDouble()), qrOnly: true, digits: 0),
  _Metric('腹囲', 'cm', (d) => _qr(d, (r) => r.waistCm), qrOnly: true),
  _Metric('右腕の筋肉', 'kg', (d) => _qr(d, (r) => r.segmentLean.rightArm), qrOnly: true, digits: 2),
  _Metric('左腕の筋肉', 'kg', (d) => _qr(d, (r) => r.segmentLean.leftArm), qrOnly: true, digits: 2),
  _Metric('体幹の筋肉', 'kg', (d) => _qr(d, (r) => r.segmentLean.trunk), qrOnly: true),
  _Metric('右脚の筋肉', 'kg', (d) => _qr(d, (r) => r.segmentLean.rightLeg), qrOnly: true, digits: 2),
  _Metric('左脚の筋肉', 'kg', (d) => _qr(d, (r) => r.segmentLean.leftLeg), qrOnly: true, digits: 2),
  _Metric('右腕の体脂肪', 'kg', (d) => _qr(d, (r) => r.segmentFat.rightArm), qrOnly: true),
  _Metric('左腕の体脂肪', 'kg', (d) => _qr(d, (r) => r.segmentFat.leftArm), qrOnly: true),
  _Metric('体幹の体脂肪', 'kg', (d) => _qr(d, (r) => r.segmentFat.trunk), qrOnly: true),
  _Metric('右脚の体脂肪', 'kg', (d) => _qr(d, (r) => r.segmentFat.rightLeg), qrOnly: true),
  _Metric('左脚の体脂肪', 'kg', (d) => _qr(d, (r) => r.segmentFat.leftLeg), qrOnly: true),
];

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
  InBodyResult? result;
  final Set<String> sources = {};

  double? get bfm {
    if (record != null) return record!.bfmKg;
    if (weight != null && pbf != null) return weight! * pbf! / 100;
    if (weight != null && lean != null) return weight! - lean!;
    return null;
  }

  double? leanOrDerived() => lean ?? (weight != null && bfm != null ? weight! - bfm! : null);
}

/// 体組成の記録（InBody の用紙 QR ＋ ヘルスコネクトの体重・体脂肪・除脂肪量）
class InBodyHistoryScreen extends StatefulWidget {
  const InBodyHistoryScreen({super.key});

  @override
  State<InBodyHistoryScreen> createState() => _InBodyHistoryScreenState();
}

class _InBodyHistoryScreenState extends State<InBodyHistoryScreen> {
  List<_BodyDay>? _days;
  _Metric _metric = _basicMetrics.first;
  final _shareKey = GlobalKey();
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
      try {
        d.result = parseInBodyQr(r.raw);
      } on InBodyFormatException {
        d.result = null;
      }
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
      appBar: AppBar(
        title: const Text('体組成の記録'),
        actions: [
          if ((days?.where((d) => d.record != null).length ?? 0) >= 2)
            IconButton(
              tooltip: '2回の測定を比較',
              icon: const Icon(Icons.compare_arrows),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => InBodyCompareScreen(
                  records: [for (final d in days!) if (d.record != null) d.record!],
                ),
              )),
            ),
          ShareButton(onPressed: days == null || days.isEmpty ? null : () => _share(days)),
        ],
      ),
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

  List<WeightEntry> _points(List<_BodyDay> days) => days.reversed
      .where((d) => _metric.of(d) != null)
      .map((d) => WeightEntry(date: d.date, kg: _metric.of(d)!))
      .toList();

  void _share(List<_BodyDay> days) {
    final pts = _points(days);
    final unit = _metric.unit;
    final text = pts.isEmpty
        ? '体組成の記録'
        : '${_metric.label}：${pts.last.kg.toStringAsFixed(_metric.digits)}$unit'
            '${pts.length >= 2 ? '（${shortDate(parseYmd(pts.first.date))}から${signed1(pts.last.kg - pts.first.kg)}$unit）' : ''}';
    shareCapture(context, _shareKey, text: text, fileName: 'body_history');
  }

  Widget _metricChips(BuildContext context, List<_Metric> metrics, bool hasQr) => Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final m in metrics)
            if (!m.qrOnly || hasQr)
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                label: Text(m.label),
                selected: _metric == m,
                onSelected: (_) => setState(() => _metric = m),
              ),
        ],
      );

  Widget _list(BuildContext context, List<_BodyDay> days) {
    final theme = Theme.of(context);
    final healthOn = s.settings.healthEnabled;

    // グラフ用：古い順
    final points = _points(days);
    final hasQr = days.any((d) => d.record != null);
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
          _metricChips(context, _basicMetrics, hasQr),
          if (hasQr)
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text('InBody 用紙の詳しい項目', style: theme.textTheme.bodyMedium),
                initiallyExpanded: _detailMetrics.contains(_metric),
                children: [_metricChips(context, _detailMetrics, hasQr)],
              ),
            ),
          const SizedBox(height: 8),
          ShareFrame(
            captureKey: _shareKey,
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_metric.label}${_metric.unit.isEmpty ? '' : '（${_metric.unit}）'}',
                        style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    if (points.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _metric.qrOnly ? 'この項目は InBody の用紙 QR から取り込んだ分だけ表示できます' : 'この項目の記録がありません',
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      WeightChart(entries: points, from: from, to: to),
                    if (points.length >= 2)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Center(
                          child: Text(
                            '最新 ${points.last.kg.toStringAsFixed(_metric.digits)}${_metric.unit}　'
                            '${shortDate(parseYmd(points.first.date))}からの変化：'
                            '${signed1(points.last.kg - points.first.kg)}${_metric.unit}',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
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
