import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/activity.dart';
import '../../core/dates.dart';
import '../../core/track.dart';
import '../../widgets/activity_card.dart';
import '../../widgets/series_chart.dart';
import '../../widgets/share_capture.dart';
import 'best_records_screen.dart';
import 'history_common.dart';
import 'strava_activity_screen.dart';
import 'strava_import_flow.dart';
import 'workouts.dart';

enum _ChartMetric {
  time('時間'),
  distance('距離'),
  kcal('カロリー'),
  count('回数'),
  elev('標高');

  const _ChartMetric(this.label);
  final String label;

  double of(Workout w) => switch (this) {
        _ChartMetric.time => w.timeS / 3600,
        _ChartMetric.distance => (w.distanceM ?? 0) / 1000,
        _ChartMetric.kcal => w.kcal,
        _ChartMetric.count => 1,
        _ChartMetric.elev => w.elevGainM ?? 0,
      };

  String format(double v) => switch (this) {
        _ChartMetric.time => '${v.toStringAsFixed(1)}h',
        _ChartMetric.distance => v >= 100 ? '${v.round()}' : v.toStringAsFixed(1),
        _ChartMetric.kcal => '${v.round()}',
        _ChartMetric.count => '${v.round()}',
        _ChartMetric.elev => '${v.round()}m',
      };
}

enum _Bucket {
  week('週'),
  month('月'),
  year('年');

  const _Bucket(this.label);
  final String label;
}

class _Totals {
  int count = 0;
  double timeS = 0;
  double distanceM = 0;
  double kcal = 0;
  double elevM = 0;

  void add(Workout w) {
    count++;
    timeS += w.timeS;
    distanceM += w.distanceM ?? 0;
    kcal += w.kcal;
    elevM += w.elevGainM ?? 0;
  }
}

String _km(double m) => '${(m / 1000).toStringAsFixed(1)}km';
String _hm(double s) {
  final m = (s / 60).round();
  return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
}

/// 運動の記録（Strava の取り込み＋ヘルスコネクト）
class ExerciseHistoryScreen extends StatefulWidget {
  const ExerciseHistoryScreen({super.key});

  @override
  State<ExerciseHistoryScreen> createState() => _ExerciseHistoryScreenState();
}

class _ExerciseHistoryScreenState extends State<ExerciseHistoryScreen> {
  HistoryPeriod _period = HistoryPeriod.year;
  WorkoutLoad? _load;
  ExerciseKind? _kind;
  _ChartMetric _metric = _ChartMetric.distance;
  _Bucket _bucket = _Bucket.month;
  final _shareKey = GlobalKey();

  AppServices get s => AppServices.I;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _load = null);
    final r = await loadWorkouts(_period.from(DateTime.now()));
    if (mounted) setState(() => _load = r);
  }

  Future<void> _requestMore() async {
    try {
      await s.health.request();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('許可画面を開けませんでした：$e')));
    }
    await _reload();
  }

  Future<void> _import() async {
    final n = await runStravaImport(context);
    if (n != null) await _reload();
  }

  List<Workout> get _visible =>
      (_load?.workouts ?? const <Workout>[]).where((w) => _kind == null || w.kind == _kind).toList();

  void _share() {
    final list = _visible;
    final t = _Totals();
    list.forEach(t.add);
    final what = _kind?.label ?? '運動';
    final text = '$what（${_period.label}）：${t.count}回・${_hm(t.timeS)}'
        '${t.distanceM > 0 ? '・${_km(t.distanceM)}' : ''}・${t.kcal.round()}kcal';
    shareCapture(context, _shareKey, text: text, fileName: 'exercise_summary');
  }

  @override
  Widget build(BuildContext context) {
    final load = _load;
    return Scaffold(
      appBar: AppBar(
        title: const Text('運動の記録'),
        actions: [
          IconButton(
            tooltip: 'ベスト記録・年間の記録',
            icon: const Icon(Icons.emoji_events_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BestRecordsScreen())),
          ),
          IconButton(tooltip: 'Strava の記録を取り込む', icon: const Icon(Icons.upload_file), onPressed: _import),
          ShareButton(onPressed: load == null || _visible.isEmpty ? null : _share),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            PeriodSelector(value: _period, onChanged: (p) {
              setState(() => _period = p);
              _reload();
            }),
            const SizedBox(height: 8),
            if (load == null)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else
              ..._content(context, load),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, WorkoutLoad load) {
    final healthOn = s.settings.healthEnabled && load.granted.contains('exercise');
    final kinds = load.workouts.map((w) => w.kind).toSet().toList()..sort((a, b) => a.index.compareTo(b.index));
    final list = _visible;
    return [
      if (load.stravaCount == 0)
        Card(
          child: ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Strava の過去の記録を取り込む'),
            subtitle: const Text('ルート・ペース・心拍・標高まで見られます'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _import,
          ),
        ),
      if (!healthOn)
        const InfoCard(text: 'ヘルスコネクトと連携すると、Strava などの新しい運動が自動で表示されます（設定 → ヘルスコネクト）。')
      else if (!load.granted.contains('history') || !load.granted.contains('distance'))
        MorePermissionCard(
          missing: [
            if (!load.granted.contains('history')) '30日より前の記録',
            if (!load.granted.contains('distance')) '距離',
          ],
          onRequest: _requestMore,
        ),
      if (load.error != null) InfoCard(text: 'ヘルスコネクトの読み取りでエラーが起きました：${load.error}'),
      if (kinds.length > 1)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: const Text('すべて'), selected: _kind == null, onSelected: (_) => setState(() => _kind = null)),
              ),
              for (final k in kinds)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    avatar: Icon(ActivityCard.iconFor(k), size: 16),
                    label: Text(k.label),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
                ),
            ],
          ),
        ),
      const SizedBox(height: 8),
      if (list.isEmpty)
        const InfoCard(text: 'この期間の運動の記録はありません。')
      else ...[
        ShareFrame(
          captureKey: _shareKey,
          child: Column(
            children: [
              _summary(context, list),
              const SizedBox(height: 8),
              _chart(context, list),
            ],
          ),
        ),
        const SizedBox(height: 4),
        ..._monthlyList(context, list),
      ],
    ];
  }

  Widget _summary(BuildContext context, List<Workout> list) {
    final t = _Totals();
    list.forEach(t.add);
    final theme = Theme.of(context);
    Widget cell(String label, String value) => Expanded(
          child: Column(
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              const SizedBox(height: 2),
              FittedBox(
                child: Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Text('${_kind?.label ?? 'すべての運動'}（${_period.label}）', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                cell('回数', '${t.count}回'),
                cell('時間', _hm(t.timeS)),
                cell('距離', t.distanceM > 0 ? _km(t.distanceM) : '−'),
                cell('獲得標高', t.elevM > 0 ? '${t.elevM.round()}m' : '−'),
                cell('消費', '${t.kcal.round()}kcal'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  DateTime _bucketStart(DateTime d) => switch (_bucket) {
        _Bucket.week => dayOnly(d).subtract(Duration(days: d.weekday - 1)),
        _Bucket.month => DateTime(d.year, d.month),
        _Bucket.year => DateTime(d.year),
      };

  DateTime _prevBucket(DateTime b) => switch (_bucket) {
        _Bucket.week => b.subtract(const Duration(days: 7)),
        _Bucket.month => DateTime(b.year, b.month - 1),
        _Bucket.year => DateTime(b.year - 1),
      };

  String _bucketLabel(DateTime b) => switch (_bucket) {
        _Bucket.week => '${b.month}/${b.day}',
        _Bucket.month => b.month == 1 ? '${b.year % 100}年1月' : '${b.month}月',
        _Bucket.year => '${b.year}',
      };

  Widget _chart(BuildContext context, List<Workout> list) {
    final theme = Theme.of(context);
    final sums = <DateTime, double>{};
    for (final w in list) {
      final k = _bucketStart(w.start);
      sums[k] = (sums[k] ?? 0) + _metric.of(w);
    }
    final oldest = _bucketStart(list.map((w) => w.start).reduce((a, b) => a.isBefore(b) ? a : b));
    final buckets = <DateTime>[];
    for (var b = _bucketStart(DateTime.now()); buckets.length < 12; b = _prevBucket(b)) {
      buckets.insert(0, b);
      if (!b.isAfter(oldest)) break;
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${_bucket.label}ごとの${_metric.label}', style: theme.textTheme.labelLarge),
                const Spacer(),
                SegmentedButton<_Bucket>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: [for (final b in _Bucket.values) ButtonSegment(value: b, label: Text(b.label))],
                  selected: {_bucket},
                  onSelectionChanged: (v) => setState(() => _bucket = v.first),
                ),
              ],
            ),
            const SizedBox(height: 8),
            PeriodBarChart(
              labels: buckets.map(_bucketLabel).toList(),
              values: buckets.map((b) => sums[b] ?? 0).toList(),
              format: _metric.format,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final m in _ChartMetric.values)
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(m.label),
                    selected: _metric == m,
                    onSelected: (_) => setState(() => _metric = m),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _monthlyList(BuildContext context, List<Workout> list) {
    final theme = Theme.of(context);
    final out = <Widget>[];
    DateTime? month;
    for (final w in list) {
      final m = DateTime(w.start.year, w.start.month);
      if (m != month) {
        month = m;
        final t = _Totals();
        list.where((x) => x.start.year == m.year && x.start.month == m.month).forEach(t.add);
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Text(
            '${m.year}年${m.month}月　${t.count}回・${_hm(t.timeS)}'
            '${t.distanceM > 0 ? '・${_km(t.distanceM)}' : ''}・${t.kcal.round()}kcal',
            style: theme.textTheme.titleSmall,
          ),
        ));
      }
      out.add(_WorkoutTile(workout: w, onChanged: _reload));
    }
    return out;
  }
}

class _WorkoutTile extends StatelessWidget {
  const _WorkoutTile({required this.workout, required this.onChanged});

  final Workout workout;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final w = workout;
    final theme = Theme.of(context);
    final pace = w.distanceM != null && w.distanceM! > 0
        ? (w.kind == ExerciseKind.biking
            ? '${(w.distanceM! / w.timeS * 3.6).toStringAsFixed(1)}km/h'
            : '${formatPace(w.timeS / w.distanceM! * 1000)}/km')
        : null;
    final id = w.stravaId;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: id == null
            ? null
            : () async {
                await Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => StravaActivityScreen(activityId: id)));
                onChanged();
              },
        leading: Icon(ActivityCard.iconFor(w.kind)),
        title: Text(w.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${shortDate(w.start)} ${w.start.hour}:${w.start.minute.toString().padLeft(2, '0')}・${formatDuration(w.timeS)}'
          '${w.distanceM != null ? '・${_km(w.distanceM!)}' : ''}${pace != null ? '・$pace' : ''}\n${w.sources.join('・')}',
        ),
        isThreeLine: true,
        trailing: Text(
          '${w.kcalEstimated ? '約' : ''}${w.kcal.round()}\nkcal',
          textAlign: TextAlign.right,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
