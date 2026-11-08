import 'package:flutter/foundation.dart';

import '../core/activity.dart';
import '../core/dates.dart';
import '../core/inbody.dart';
import '../data/app_db.dart';
import '../data/app_settings.dart';
import '../data/entities.dart';
import 'health_service.dart';

/// ヘルスコネクト → 端末DB の取り込み
/// - 体重・体脂肪率：日ごとに最新の値を weights へ（手入力・InBody QR の日は上書きしない）
/// - 歩数・エクササイズ：日ごとの消費カロリーを計算して activity_days へ
/// アプリ起動時・復帰時・ホームの引っ張り更新で呼ぶ（バックグラウンド実行はしない）
class ActivitySync {
  ActivitySync({required this.health, required this.db, required this.settings});

  final HealthService health;
  final AppDb db;
  final AppSettings settings;

  /// 取り込みで内容が変わったら増える（画面の再読み込み用）
  final ValueNotifier<int> revision = ValueNotifier(0);

  static const _minInterval = Duration(minutes: 5);
  static const _maxDaysBack = 30;

  DateTime? _lastRun;
  Future<String?>? _running;

  /// 取り込みを実行。結果の一言（エラー時はその内容）を返す。連携オフなら null
  Future<String?> sync({bool force = false, List<DateTime> days = const []}) {
    if (!settings.healthEnabled) return Future.value(null);
    if (_running != null) return _running!;
    final last = _lastRun;
    if (!force && days.isEmpty && last != null && DateTime.now().difference(last) < _minInterval) {
      return Future.value(null);
    }
    _running = _run(days).whenComplete(() => _running = null);
    return _running!;
  }

  Future<String?> _run(List<DateTime> extraDays) async {
    try {
      if (await health.status() != HealthStatus.available) return 'ヘルスコネクトが使えません';
      final granted = await health.granted();
      if (granted.isEmpty) return 'ヘルスコネクトの権限がありません';

      final weights = await _syncBody(granted);

      final today = dayOnly(DateTime.now());
      final targets = <String, DateTime>{
        ymd(today): today,
        ymd(addDays(today, -1)): addDays(today, -1),
      };
      for (final d in extraDays) {
        final day = dayOnly(d);
        if (day.isAfter(today) || today.difference(day).inDays > _maxDaysBack) continue;
        targets[ymd(day)] = day;
      }
      for (final day in targets.values) {
        await _syncDay(day, granted);
      }
      _lastRun = DateTime.now();
      revision.value++;
      return weights > 0 ? '体重を$weights件取り込みました' : '同期しました';
    } catch (e) {
      debugPrint('health sync failed: $e');
      return '同期に失敗しました：$e';
    }
  }

  /// 体重・体脂肪・身長。取り込んだ体重の件数を返す
  Future<int> _syncBody(Set<String> granted) async {
    if (!granted.contains('weight') && !granted.contains('bodyFat') && !granted.contains('height')) return 0;
    final now = DateTime.now();
    final last = settings.healthBodySyncedAt;
    final from = last == null ? now.subtract(const Duration(days: _maxDaysBack)) : last.subtract(const Duration(days: 2));
    final body = await health.readBody(from, now);

    final weightByDay = _latestPerDay(body.weight);
    final fatByDay = _latestPerDay(body.bodyFat);
    var count = 0;
    for (final MapEntry(key: date, value: w) in weightByDay.entries) {
      if (w.value < 20 || w.value > 300) continue;
      final fat = fatByDay[date]?.value;
      final saved = await db.importHealthWeight(WeightEntry(
        date: date,
        kg: double.parse(w.value.toStringAsFixed(1)),
        source: WeightEntry.sourceHealth,
        bodyFatPct: fat == null ? null : double.parse(fat.toStringAsFixed(1)),
      ));
      if (saved) count++;
    }

    if (body.height.isNotEmpty) {
      final h = body.height.reduce((a, b) => b.time.isAfter(a.time) ? b : a);
      final cm = h.value * 100;
      if (cm >= 80 && cm <= 250) await settings.set('auto_height_cm', cm.toStringAsFixed(1));
    }
    await settings.set('health_body_synced_at', now.toIso8601String());
    return count;
  }

  static Map<String, HealthSample> _latestPerDay(List<HealthSample> list) {
    final out = <String, HealthSample>{};
    for (final s in list) {
      final d = ymd(s.time);
      final cur = out[d];
      if (cur == null || s.time.isAfter(cur.time)) out[d] = s;
    }
    return out;
  }

  Future<void> _syncDay(DateTime day, Set<String> granted) async {
    if (!granted.contains('steps') && !granted.contains('exercise')) return;
    final start = dayOnly(day);
    final dayEnd = addDays(start, 1);
    final now = DateTime.now();
    final end = now.isBefore(dayEnd) ? now : dayEnd;
    if (!end.isAfter(start)) return;

    final sessions = granted.contains('exercise') ? await health.readSessions(start, end) : <ExerciseSession>[];
    final groups = groupSessions(sessions, start, end);
    final totals = await health.aggregate([
      (start, end),
      for (final g in groups) (g.start, g.end),
    ]);
    if (totals.isEmpty) return;

    final weightKg = (await db.weightOnOrBefore(ymd(start)))?.kg ?? fallbackWeightKg;
    final burn = computeDayBurn(
      day: totals.first,
      groups: groups,
      perGroup: totals.sublist(1),
      heightCm: await heightCm(),
      weightKg: weightKg,
    );
    await db.saveActivity(ActivityDay(
      date: ymd(start),
      totalSteps: burn.totalSteps,
      walkSteps: burn.walkSteps,
      walkKcal: burn.walkKcal,
      exercises: burn.exercises,
      syncedAt: now,
    ));
  }

  /// 計算に使う身長：設定の手入力 → ヘルスコネクト → 最新の InBody → 仮の値
  Future<double> heightCm() async => (await heightSource()).$1;

  /// (身長cm, どこの値か)
  Future<(double, String)> heightSource() async {
    final manual = settings.heightCm;
    if (manual != null) return (manual, '手入力');
    final auto = settings.autoHeightCm;
    if (auto != null && auto >= 80 && auto <= 250) return (auto, 'ヘルスコネクト');
    final ib = await db.inbodyResults();
    for (final r in ib) {
      try {
        final h = parseInBodyQr(r.raw).heightCm;
        if (h >= 80 && h <= 250) return (h, 'InBody');
      } catch (_) {}
    }
    return (fallbackHeightCm, '仮の値');
  }
}
