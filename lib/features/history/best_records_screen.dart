import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/strava_archive.dart';
import '../../core/track.dart';
import '../../widgets/activity_card.dart';
import '../../widgets/share_capture.dart';
import 'strava_activity_screen.dart';

class _Year {
  int count = 0;
  double distanceM = 0;
  double timeS = 0;
  double elevM = 0;
}

/// ランニングのベスト記録と、年ごとの合計（Strava の取り込みから）
class BestRecordsScreen extends StatefulWidget {
  const BestRecordsScreen({super.key});

  @override
  State<BestRecordsScreen> createState() => _BestRecordsScreenState();
}

class _BestRecordsScreenState extends State<BestRecordsScreen> {
  List<StravaActivity>? _runs;
  List<StravaActivity> _all = const [];
  final _shareKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppServices.I.db;
    final runs = await db.stravaRunsWithBests();
    final all = await db.stravaActivities();
    if (mounted) {
      setState(() {
        _runs = runs;
        _all = all;
      });
    }
  }

  /// 距離ごとに速い順の上位3件
  Map<String, List<(StravaActivity, double)>> _tops(List<StravaActivity> runs) {
    final out = <String, List<(StravaActivity, double)>>{};
    for (final (label, _) in bestEffortDistances) {
      final list = [
        for (final r in runs)
          if (r.bestEfforts[label] != null) (r, r.bestEfforts[label]!),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      if (list.isNotEmpty) out[label] = list.take(3).toList();
    }
    return out;
  }

  void _share(Map<String, List<(StravaActivity, double)>> tops) {
    final text = [
      'ランニングのベスト記録',
      for (final e in tops.entries) '${e.key} ${formatDuration(e.value.first.$2)}',
    ].join('\n');
    shareCapture(context, _shareKey, text: text, fileName: 'best_records');
  }

  void _open(StravaActivity a) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => StravaActivityScreen(activityId: a.id)));

  @override
  Widget build(BuildContext context) {
    final runs = _runs;
    final tops = runs == null ? const <String, List<(StravaActivity, double)>>{} : _tops(runs);
    return Scaffold(
      appBar: AppBar(
        title: const Text('ベスト記録・年間の記録'),
        actions: [ShareButton(onPressed: tops.isEmpty ? null : () => _share(tops))],
      ),
      body: runs == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (_all.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Strava の記録を取り込むと、ベスト記録と年ごとの合計が表示されます（運動の記録 → 右上の取り込みボタン）。'),
                    ),
                  ),
                if (tops.isNotEmpty) ShareFrame(captureKey: _shareKey, child: _bestsCard(context, tops)),
                if (_all.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _yearsCard(context),
                ],
              ],
            ),
    );
  }

  Widget _bestsCard(BuildContext context, Map<String, List<(StravaActivity, double)>> tops) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.emoji_events, color: Color(0xFFFFB300)),
                const SizedBox(width: 6),
                Text('ランニングのベスト記録', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            for (final e in tops.entries) ...[
              const Divider(height: 16),
              Text(e.key, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              for (var i = 0; i < e.value.length; i++)
                InkWell(
                  onTap: () => _open(e.value[i].$1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(width: 24, child: Text('${i + 1}', style: theme.textTheme.bodySmall)),
                        Expanded(
                          child: Text(
                            '${e.value[i].$1.start.year}/${e.value[i].$1.start.month}/${e.value[i].$1.start.day}　'
                            '${e.value[i].$1.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          formatDuration(e.value[i].$2),
                          style: TextStyle(fontWeight: i == 0 ? FontWeight.bold : FontWeight.normal),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _yearsCard(BuildContext context) {
    final theme = Theme.of(context);
    final byYear = <int, Map<String, _Year>>{};
    for (final a in _all) {
      final y = byYear.putIfAbsent(a.start.year, () => {}).putIfAbsent(a.kind.label, _Year.new);
      y.count++;
      y.distanceM += a.distanceM;
      y.timeS += a.movingS;
      y.elevM += a.elevGainM ?? 0;
    }
    final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('年ごとの合計（取り込んだ Strava の記録）', style: theme.textTheme.titleMedium),
            for (final y in years) ...[
              const Divider(height: 16),
              Text('$y年', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              for (final e in byYear[y]!.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(
                        ActivityCard.iconFor(_all.firstWhere((a) => a.kind.label == e.key).kind),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      SizedBox(width: 90, child: Text(e.key)),
                      Expanded(
                        child: Text(
                          '${e.value.count}回・${(e.value.distanceM / 1000).toStringAsFixed(0)}km・'
                          '${(e.value.timeS / 3600).toStringAsFixed(1)}時間'
                          '${e.value.elevM > 0 ? '・↑${e.value.elevM.round()}m' : ''}',
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
