import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/activity.dart';
import '../../core/dates.dart';
import '../../widgets/activity_card.dart';
import 'history_common.dart';

/// 1回分の運動（重なる記録をまとめたあと）
class _Workout {
  _Workout(this.group, double weightKg)
      : kind = group.main.kind,
        title = group.main.title,
        start = group.start,
        end = group.end,
        distanceM = _maxOf(group.sessions.map((s) => s.distanceM)),
        recordedKcal = _maxOf(group.sessions.map((s) => s.kcal)),
        estimatedKcal = estimateExerciseKcal(group.main.kind, group.end.difference(group.start), weightKg);

  final ExerciseGroup group;
  final ExerciseKind kind;
  final String? title;
  final DateTime start;
  final DateTime end;
  final double? distanceM;
  final double? recordedKcal;
  final double estimatedKcal;

  Duration get duration => end.difference(start);
  double get kcal => recordedKcal ?? estimatedKcal;
  bool get kcalEstimated => recordedKcal == null;

  static double? _maxOf(Iterable<double?> v) {
    final list = v.whereType<double>().toList();
    if (list.isEmpty) return null;
    return list.reduce((a, b) => a > b ? a : b);
  }
}

class _Totals {
  int count = 0;
  Duration time = Duration.zero;
  double distanceM = 0;
  double kcal = 0;

  void add(_Workout w) {
    count++;
    time += w.duration;
    distanceM += w.distanceM ?? 0;
    kcal += w.kcal;
  }
}

String _hm(Duration d) => '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}';
String _km(double m) => '${(m / 1000).toStringAsFixed(1)}km';

/// Strava などがヘルスコネクトに記録した運動の履歴
class ExerciseHistoryScreen extends StatefulWidget {
  const ExerciseHistoryScreen({super.key});

  @override
  State<ExerciseHistoryScreen> createState() => _ExerciseHistoryScreenState();
}

class _ExerciseHistoryScreenState extends State<ExerciseHistoryScreen> {
  HistoryPeriod _period = HistoryPeriod.year;
  List<_Workout>? _workouts;
  Set<String> _granted = {};
  String? _error;

  AppServices get s => AppServices.I;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _workouts = null;
      _error = null;
    });
    try {
      final granted = await s.health.granted();
      final now = DateTime.now();
      final from = _period.from(now);
      final sessions = granted.contains('exercise')
          ? await s.health.readSessions(from, now, metrics: true)
          : <ExerciseSession>[];
      final w = await s.db.weightOnOrBefore(ymd(now));
      final weight = w?.kg ?? 60;
      final workouts = groupSessions(sessions, from, now).map((g) => _Workout(g, weight)).toList()
        ..sort((a, b) => b.start.compareTo(a.start));
      if (!mounted) return;
      setState(() {
        _granted = granted;
        _workouts = workouts;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _workouts = const [];
        _error = '$e';
      });
    }
  }

  Future<void> _requestMore() async {
    try {
      await s.health.request();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('許可画面を開けませんでした：$e')));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _workouts;
    return Scaffold(
      appBar: AppBar(title: const Text('運動の記録')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            PeriodSelector(value: _period, onChanged: (p) {
              setState(() => _period = p);
              _load();
            }),
            const SizedBox(height: 8),
            if (!s.settings.healthEnabled || !_granted.contains('exercise'))
              const InfoCard(text: 'ヘルスコネクトと連携すると、Strava などが記録した運動がここに表示されます（設定 → ヘルスコネクト）。')
            else if (!_granted.contains('history') || !_granted.contains('distance'))
              MorePermissionCard(
                missing: [
                  if (!_granted.contains('history')) '30日より前の記録',
                  if (!_granted.contains('distance')) '距離',
                ],
                onRequest: _requestMore,
              ),
            if (_error != null) InfoCard(text: '読み取りでエラーが起きました：$_error'),
            if (list == null)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (list.isEmpty)
              const InfoCard(text: 'この期間の運動の記録はありません。')
            else ...[
              _summary(context, list),
              const SizedBox(height: 12),
              _monthlyChart(context, list),
              const SizedBox(height: 12),
              ..._monthlyList(context, list),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summary(BuildContext context, List<_Workout> list) {
    final t = _Totals();
    list.forEach(t.add);
    final theme = Theme.of(context);
    Widget cell(String label, String value) => Expanded(
          child: Column(
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          children: [
            cell('回数', '${t.count}回'),
            cell('時間', _hm(t.time)),
            cell('距離', t.distanceM > 0 ? _km(t.distanceM) : '−'),
            cell('消費', '${t.kcal.round()}kcal'),
          ],
        ),
      ),
    );
  }

  /// 月ごとの運動時間の棒グラフ（直近12か月まで）
  Widget _monthlyChart(BuildContext context, List<_Workout> list) {
    final theme = Theme.of(context);
    final byMonth = <DateTime, _Totals>{};
    for (final w in list) {
      byMonth.putIfAbsent(DateTime(w.start.year, w.start.month), _Totals.new).add(w);
    }
    final now = DateTime.now();
    final first = list.map((w) => w.start).reduce((a, b) => a.isBefore(b) ? a : b);
    final months = <DateTime>[];
    for (var m = DateTime(now.year, now.month); months.length < 12; m = DateTime(m.year, m.month - 1)) {
      months.insert(0, m);
      if (!m.isAfter(DateTime(first.year, first.month))) break;
    }
    final maxMin = months.map((m) => byMonth[m]?.time.inMinutes ?? 0).fold(1, (a, b) => a > b ? a : b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('月ごとの運動時間', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final m in months)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              (byMonth[m]?.time.inMinutes ?? 0) == 0 ? '' : '${(byMonth[m]!.time.inMinutes / 60).toStringAsFixed(1)}h',
                              style: const TextStyle(fontSize: 9),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              height: 80 * (byMonth[m]?.time.inMinutes ?? 0) / maxMin,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('${m.month}月', style: const TextStyle(fontSize: 10)),
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

  List<Widget> _monthlyList(BuildContext context, List<_Workout> list) {
    final theme = Theme.of(context);
    final out = <Widget>[];
    DateTime? month;
    for (var i = 0; i < list.length; i++) {
      final w = list[i];
      final m = DateTime(w.start.year, w.start.month);
      if (m != month) {
        month = m;
        final t = _Totals();
        list.where((x) => x.start.year == m.year && x.start.month == m.month).forEach(t.add);
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Text(
            '${m.year}年${m.month}月　${t.count}回・${_hm(t.time)}'
            '${t.distanceM > 0 ? '・${_km(t.distanceM)}' : ''}・${t.kcal.round()}kcal',
            style: theme.textTheme.titleSmall,
          ),
        ));
      }
      final origins = w.group.origins.map(originLabel).join('・');
      out.add(Card(
        margin: const EdgeInsets.only(bottom: 6),
        child: ListTile(
          leading: Icon(ActivityCard.iconFor(w.kind)),
          title: Text(w.title?.isNotEmpty == true ? w.title! : w.kind.label),
          subtitle: Text(
            '${shortDate(w.start)} ${w.start.hour}:${w.start.minute.toString().padLeft(2, '0')}・${_hm(w.duration)}'
            '${w.distanceM != null ? '・${_km(w.distanceM!)}' : ''}　$origins',
          ),
          trailing: Text(
            '${w.kcalEstimated ? '約' : ''}${w.kcal.round()}\nkcal',
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ));
    }
    return out;
  }
}
