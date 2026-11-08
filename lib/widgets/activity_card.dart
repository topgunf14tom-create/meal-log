import 'package:flutter/material.dart';

import '../core/activity.dart';
import '../core/format.dart';
import '../data/entities.dart';

/// ホームの「消費カロリー」カード（歩数＋運動）
class ActivityCard extends StatelessWidget {
  const ActivityCard({super.key, required this.activity, required this.onRefresh, this.onHistory});

  final ActivityDay? activity;
  final VoidCallback onRefresh;

  /// 運動の履歴を開く
  final VoidCallback? onHistory;

  static String _hm(DateTime t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

  static IconData iconFor(ExerciseKind k) => _icon(k);

  static IconData _icon(ExerciseKind k) => switch (k) {
        ExerciseKind.running => Icons.directions_run,
        ExerciseKind.walking || ExerciseKind.hiking => Icons.directions_walk,
        ExerciseKind.biking => Icons.directions_bike,
        ExerciseKind.swimming => Icons.pool,
        ExerciseKind.strength || ExerciseKind.hiit => Icons.fitness_center,
        ExerciseKind.yoga => Icons.self_improvement,
        ExerciseKind.snow => Icons.downhill_skiing,
        ExerciseKind.other => Icons.sports,
      };

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('消費カロリー', style: theme.textTheme.labelLarge),
                const Spacer(),
                if (a != null) Text('${kcal0(a.totalKcal)} kcal', style: theme.textTheme.titleMedium),
                if (onHistory != null)
                  IconButton(
                    tooltip: '運動の記録',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.history, size: 20),
                    onPressed: onHistory,
                  ),
                IconButton(
                  tooltip: 'ヘルスコネクトから更新',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.sync, size: 20),
                  onPressed: onRefresh,
                ),
              ],
            ),
            if (a == null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('この日のデータはまだありません（ヘルスコネクトは直近30日分まで読めます）', style: small),
              )
            else ...[
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.directions_walk),
                title: Text('${_steps(a.totalSteps)} 歩'),
                subtitle: a.walkSteps != a.totalSteps ? Text('運動中を除く ${_steps(a.walkSteps)} 歩で計算') : null,
                trailing: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('${kcal0(a.walkKcal)} kcal'),
                ),
              ),
              for (final e in a.exercises)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_icon(e.kind)),
                  title: Text(e.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${_hm(e.start)}〜${_hm(e.end)}（${e.duration.inMinutes}分）'
                    '${e.origins.isEmpty ? '' : '・${e.origins.map(originLabel).join('/')}'}',
                  ),
                  trailing: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text('${e.estimated ? '約' : ''}${kcal0(e.kcal)} kcal'),
                  ),
                ),
              Text('更新 ${_hm(a.syncedAt)}　※歩行は体重×距離×0.5、運動は活動カロリー（無ければ推定）', style: small),
            ],
          ],
        ),
      ),
    );
  }

  static String _steps(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}
