import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/dates.dart';
import '../../core/forecast.dart';
import '../../core/nutrition.dart';
import '../../data/entities.dart';
import '../../services/forecast_loader.dart';
import '../../services/nutrition_service.dart';
import '../../widgets/forecast_card.dart';
import '../../widgets/share_capture.dart';

enum _Span {
  week('週'),
  month('月');

  const _Span(this.label);
  final String label;
}

/// 1日分
class _Day {
  _Day(this.date, this.intake, this.target, this.burn);

  final DateTime date;
  final Pfc? intake;
  final double target;
  final double burn;

  bool get recorded => intake != null && intake!.kcal > 0;
}

class _Report {
  _Report({
    required this.from,
    required this.to,
    required this.days,
    required this.goal,
    required this.weightStart,
    required this.weightEnd,
    required this.forecast,
  });

  final DateTime from;
  final DateTime to;
  final List<_Day> days;
  final Goal goal;
  final WeightEntry? weightStart;
  final WeightEntry? weightEnd;
  final WeightForecast? forecast;

  List<_Day> get recorded => days.where((d) => d.recorded).toList();

  double _avg(Iterable<double> v) => v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

  double get avgIntake => _avg(recorded.map((d) => d.intake!.kcal));
  double get avgTarget => _avg(recorded.map((d) => d.target));
  double get avgBurn => _avg(days.where((d) => d.burn > 0).map((d) => d.burn));
  Pfc get avgPfc {
    final r = recorded;
    if (r.isEmpty) return Pfc.zero;
    final sum = r.fold<Pfc>(Pfc.zero, (a, d) => a + d.intake!);
    return Pfc(sum.kcal / r.length, sum.p / r.length, sum.f / r.length, sum.c / r.length);
  }

  int get overDays => recorded.where((d) => d.intake!.kcal > d.target).length;
}

/// 週・月のレポート（平均の摂取・PFC・目標との差・消費・体重の変化、AI の振り返り）
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  _Span _span = _Span.week;

  /// 0 = 今週・今月、-1 = 先週・先月 …
  int _offset = 0;
  _Report? _report;
  final _comments = <String, String>{};
  bool _commentBusy = false;
  final _shareKey = GlobalKey();

  AppServices get s => AppServices.I;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) _range() {
    final today = dayOnly(DateTime.now());
    if (_span == _Span.week) {
      final monday = addDays(today, -(today.weekday - 1) + 7 * _offset);
      return (monday, addDays(monday, 6));
    }
    final first = DateTime(today.year, today.month + _offset);
    return (first, DateTime(first.year, first.month + 1, 0));
  }

  String get _key => '${_span.name}:$_offset';

  String _title(DateTime from, DateTime to) => _span == _Span.week
      ? '${from.month}/${from.day}〜${to.month}/${to.day}'
      : '${from.year}年${from.month}月';

  Future<void> _load() async {
    setState(() => _report = null);
    final (from, to) = _range();
    final today = dayOnly(DateTime.now());
    final end = to.isAfter(today) ? today : to;
    final totals = await s.db.dailyTotals(ymd(from), ymd(end));
    final acts = {for (final a in await s.db.activitiesBetween(ymd(from), ymd(end))) a.date: a};
    final healthOn = s.settings.healthEnabled;
    final days = <_Day>[];
    for (var d = from; !d.isAfter(end); d = addDays(d, 1)) {
      final key = ymd(d);
      final g = await s.db.goalOn(key);
      final double burn = healthOn ? (acts[key]?.totalKcal ?? 0.0) : 0.0;
      days.add(_Day(d, totals[key], g.targetKcal + (s.settings.addBurnToGoal ? burn : 0), burn));
    }
    final goal = await s.db.goalOn(ymd(end));
    final weights = (await s.db.weightsSince(ymd(from))).where((w) => w.date.compareTo(ymd(end)) <= 0).toList();
    final forecast = await loadForecast(from, end);
    if (!mounted) return;
    setState(() {
      _report = _Report(
        from: from,
        to: to,
        days: days,
        goal: goal,
        weightStart: weights.isEmpty ? null : weights.first,
        weightEnd: weights.isEmpty ? null : weights.last,
        forecast: forecast,
      );
    });
  }

  void _move(int delta) {
    setState(() => _offset += delta);
    _load();
  }

  Map<String, Object?> _summary(_Report r) {
    final pfc = r.avgPfc;
    final ratio = pfc.energyRatio();
    return {
      '期間': '${ymd(r.from)}〜${ymd(r.days.isEmpty ? r.to : r.days.last.date)}（${_span.label}）',
      '記録した日数': '${r.recorded.length} / ${r.days.length}',
      '1日平均の摂取kcal': r.avgIntake.round(),
      '1日平均の目標kcal': r.avgTarget.round(),
      '目標を超えた日数': r.overDays,
      '1日平均のPFC_g': {'P': pfc.p.round(), 'F': pfc.f.round(), 'C': pfc.c.round()},
      'PFC比率_%': {'P': ratio.p.round(), 'F': ratio.f.round(), 'C': ratio.c.round()},
      '目標のPFC比率_%': {'P': r.goal.pRatio, 'F': r.goal.fRatio, 'C': r.goal.cRatio},
      if (r.avgBurn > 0) '1日平均の歩行・運動kcal': r.avgBurn.round(),
      if (r.weightStart != null && r.weightEnd != null)
        '体重': '${r.weightStart!.kg.toStringAsFixed(1)}kg → ${r.weightEnd!.kg.toStringAsFixed(1)}kg',
      '日ごとの摂取kcal': {for (final d in r.recorded) '${d.date.month}/${d.date.day}': d.intake!.kcal.round()},
    };
  }

  Future<void> _comment(_Report r) async {
    if (!await s.keys.hasKey()) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('AI の振り返りには Claude APIキーが必要です（設定から登録）')));
      }
      return;
    }
    setState(() => _commentBusy = true);
    try {
      final text = await s.nutrition.reportComment(_summary(r));
      if (mounted) setState(() => _comments[_key] = text);
    } on MissingApiKeyException {
      // 上で確認済み
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('振り返りを作れませんでした：$e')));
    } finally {
      if (mounted) setState(() => _commentBusy = false);
    }
  }

  void _share(_Report r) {
    final pfc = r.avgPfc.energyRatio();
    final text = '${_title(r.from, r.to)}の食事：1日平均 ${r.avgIntake.round()}kcal（目標 ${r.avgTarget.round()}）・'
        'PFC ${pfc.p.round()}/${pfc.f.round()}/${pfc.c.round()}・記録 ${r.recorded.length}/${r.days.length}日';
    shareCapture(context, _shareKey, text: text, fileName: 'report_${_span.name}');
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    final (from, to) = _range();
    return Scaffold(
      appBar: AppBar(
        title: const Text('レポート'),
        actions: [ShareButton(onPressed: r == null || r.recorded.isEmpty ? null : () => _share(r))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SegmentedButton<_Span>(
            showSelectedIcon: false,
            segments: [for (final sp in _Span.values) ButtonSegment(value: sp, label: Text(sp.label))],
            selected: {_span},
            onSelectionChanged: (v) {
              setState(() {
                _span = v.first;
                _offset = 0;
              });
              _load();
            },
          ),
          Row(
            children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _move(-1)),
              Expanded(
                child: Text(_title(from, to), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: _offset >= 0 ? null : () => _move(1)),
            ],
          ),
          if (r == null)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (r.recorded.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('この期間の食事の記録はありません。')))
          else ...[
            ShareFrame(
              captureKey: _shareKey,
              child: Column(
                children: [
                  _summaryCard(context, r),
                  const SizedBox(height: 12),
                  _dailyCard(context, r),
                  const SizedBox(height: 12),
                  _pfcCard(context, r),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (r.forecast != null) ...[
              ForecastCard(forecast: r.forecast!, currentKg: r.weightEnd?.kg, title: 'この期間のペースが続くと'),
              const SizedBox(height: 12),
            ],
            _commentCard(context, r),
          ],
        ],
      ),
    );
  }

  Widget _summaryCard(BuildContext context, _Report r) {
    final theme = Theme.of(context);
    final diff = r.avgIntake - r.avgTarget;
    Widget cell(String label, String value, {Color? color}) => Expanded(
          child: Column(
            children: [
              Text(label, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
              const SizedBox(height: 2),
              FittedBox(
                child: Text(value,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: color)),
              ),
            ],
          ),
        );
    final ws = r.weightStart, we = r.weightEnd;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Row(
              children: [
                cell('1日平均の摂取', '${r.avgIntake.round()}kcal'),
                cell('目標との差', '${diff >= 0 ? '+' : ''}${diff.round()}kcal',
                    color: diff > 0 ? const Color(0xFFE65100) : const Color(0xFF2E7D5B)),
                cell('記録した日', '${r.recorded.length}/${r.days.length}日'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                cell('目標を超えた日', '${r.overDays}日'),
                cell('歩行・運動', r.avgBurn > 0 ? '${r.avgBurn.round()}kcal/日' : '−'),
                cell(
                  '体重',
                  (ws != null && we != null && ws.date != we.date)
                      ? '${(we.kg - ws.kg) >= 0 ? '+' : ''}${(we.kg - ws.kg).toStringAsFixed(1)}kg'
                      : (we != null ? '${we.kg.toStringAsFixed(1)}kg' : '−'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dailyCard(BuildContext context, _Report r) {
    final theme = Theme.of(context);
    final maxV = r.days.fold<double>(1, (a, d) => math.max(a, math.max(d.intake?.kcal ?? 0, d.target)));
    final many = r.days.length > 10;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('日ごとの摂取', style: theme.textTheme.labelLarge),
                const Spacer(),
                Text('— 目標', style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 130,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in r.days)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: many ? 0.5 : 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            SizedBox(
                              height: 100,
                              child: Stack(
                                alignment: Alignment.bottomCenter,
                                children: [
                                  Container(
                                    height: 100 * (d.intake?.kcal ?? 0) / maxV,
                                    decoration: BoxDecoration(
                                      color: !d.recorded
                                          ? Colors.transparent
                                          : d.intake!.kcal > d.target
                                              ? const Color(0xFFFFA726)
                                              : theme.colorScheme.primary,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 100 * d.target / maxV,
                                    left: 0,
                                    right: 0,
                                    child: Container(height: 1.5, color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _span == _Span.week
                                  ? '月火水木金土日'[d.date.weekday - 1]
                                  : (d.date.day == 1 || d.date.day % 5 == 0 ? '${d.date.day}' : ''),
                              style: const TextStyle(fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pfcCard(BuildContext context, _Report r) {
    final theme = Theme.of(context);
    final pfc = r.avgPfc;
    final ratio = pfc.energyRatio();
    final target = targetGrams(r.goal);
    Widget row(String label, double g, double tg, double pct, int tpct, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(width: 72, child: Text(label)),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => Stack(
                    children: [
                      Container(height: 10, color: color.withValues(alpha: 0.15)),
                      Container(
                        height: 10,
                        width: c.maxWidth * (tg <= 0 ? 0 : (g / tg).clamp(0.0, 1.0)),
                        color: color,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 118,
                child: Text(
                  '${g.round()}/${tg.round()}g ${pct.round()}%（目標$tpct）',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1日平均のPFC', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            row('たんぱく質', pfc.p, target.p, ratio.p, r.goal.pRatio, const Color(0xFFE57373)),
            row('脂質', pfc.f, target.f, ratio.f, r.goal.fRatio, const Color(0xFFFFB74D)),
            row('炭水化物', pfc.c, target.c, ratio.c, r.goal.cRatio, const Color(0xFF64B5F6)),
          ],
        ),
      ),
    );
  }

  Widget _commentCard(BuildContext context, _Report r) {
    final theme = Theme.of(context);
    final text = _comments[_key];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 18),
                const SizedBox(width: 6),
                Text('AI の振り返り', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            if (text != null) SelectableText(text),
            if (text == null)
              Text('この期間の集計（数値のみ）を Claude（Haiku）に送り、振り返りを書いてもらいます。1回1円未満の目安です。',
                  style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: _commentBusy ? null : () => _comment(r),
                child: Text(_commentBusy ? '作成中…' : (text == null ? '振り返りを作る' : 'もう一度作る')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
