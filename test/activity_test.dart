import 'package:flutter_test/flutter_test.dart';
import 'package:meal_log/core/activity.dart';
import 'package:meal_log/data/entities.dart';

DateTime t(int h, [int m = 0]) => DateTime(2026, 11, 8, h, m);

ExerciseSession run(DateTime s, DateTime e, {String origin = 'com.strava', ExerciseKind kind = ExerciseKind.running}) =>
    ExerciseSession(start: s, end: e, kind: kind, origin: origin);

void main() {
  group('歩数→カロリー', () {
    test('身長172cm・体重70kg・8000歩 → 約6.2km・約217kcal', () {
      expect(strideMeters(172), closeTo(0.774, 0.0001));
      expect(walkDistanceKm(8000, 172), closeTo(6.192, 0.001));
      expect(walkKcal(8000, heightCm: 172, weightKg: 70), closeTo(216.7, 0.1));
    });

    test('0歩は0kcal', () {
      expect(walkKcal(0, heightCm: 170, weightKg: 60), 0);
    });
  });

  group('運動の推定カロリー', () {
    test('ランニング30分・70kg → (9.8-1)×70×0.5', () {
      expect(estimateExerciseKcal(ExerciseKind.running, const Duration(minutes: 30), 70), closeTo(308, 0.01));
    });

    test('未知の種類は「運動」扱い', () {
      expect(ExerciseKind.fromKey('xyz'), ExerciseKind.other);
      expect(ExerciseKind.fromKey(null), ExerciseKind.other);
    });
  });

  group('運動のまとめ', () {
    final dayStart = DateTime(2026, 11, 8);
    final dayEnd = DateTime(2026, 11, 9);

    test('重なる記録（Strava と Fit の同じラン）は1つにまとめる', () {
      final g = groupSessions([
        run(t(7), t(7, 40)),
        run(t(7, 2), t(7, 38), origin: 'com.google.android.apps.fitness'),
        run(t(18), t(18, 30), kind: ExerciseKind.walking),
      ], dayStart, dayEnd);
      expect(g.length, 2);
      expect(g[0].start, t(7));
      expect(g[0].end, t(7, 40));
      expect(g[0].origins.toSet(), {'com.strava', 'com.google.android.apps.fitness'});
      expect(g[0].main.origin, 'com.strava'); // 一番長い記録
      expect(g[1].main.kind, ExerciseKind.walking);
    });

    test('日をまたぐ運動はその日の分だけ', () {
      final g = groupSessions([run(DateTime(2026, 11, 7, 23, 30), t(0, 30))], dayStart, dayEnd);
      expect(g.single.start, dayStart);
      expect(g.single.end, t(0, 30));
    });

    test('範囲外は除外', () {
      expect(groupSessions([run(DateTime(2026, 11, 7, 7), DateTime(2026, 11, 7, 8))], dayStart, dayEnd), isEmpty);
    });
  });

  group('1日の消費カロリー', () {
    final groups = groupSessions([run(t(7), t(7, 30))], DateTime(2026, 11, 8), DateTime(2026, 11, 9));

    test('運動中の歩数は歩行から除き、運動は活動カロリーを使う', () {
      final b = computeDayBurn(
        day: const RangeTotals(steps: 12000, kcal: 900),
        groups: groups,
        perGroup: const [RangeTotals(steps: 4000, kcal: 320)],
        heightCm: 172,
        weightKg: 70,
      );
      expect(b.totalSteps, 12000);
      expect(b.walkSteps, 8000);
      expect(b.walkKcal, closeTo(216.7, 0.1));
      expect(b.exercises.single.kcal, 320);
      expect(b.exercises.single.estimated, isFalse);
      // 1日の活動カロリー(900)は使わない
      expect(b.totalKcal, closeTo(536.7, 0.1));
    });

    test('活動カロリーが無ければ METs で推定', () {
      final b = computeDayBurn(
        day: const RangeTotals(steps: 5000),
        groups: groups,
        perGroup: const [RangeTotals(steps: 4000)],
        heightCm: 170,
        weightKg: 70,
      );
      expect(b.exercises.single.estimated, isTrue);
      expect(b.exercises.single.kcal, closeTo(308, 0.01));
      expect(b.walkSteps, 1000);
    });

    test('運動中の歩数が合計を超えても歩行はマイナスにならない', () {
      final b = computeDayBurn(
        day: const RangeTotals(steps: 100),
        groups: groups,
        perGroup: const [RangeTotals(steps: 500, kcal: 10)],
        heightCm: 170,
        weightKg: 60,
      );
      expect(b.walkSteps, 0);
      expect(b.walkKcal, 0);
    });

    test('歩数の権限が無いとき（null）は0歩', () {
      final b = computeDayBurn(
        day: const RangeTotals(),
        groups: const [],
        perGroup: const [],
        heightCm: 170,
        weightKg: 60,
      );
      expect(b.totalSteps, 0);
      expect(b.totalKcal, 0);
    });
  });

  group('保存形式', () {
    test('ActivityDay の DB 往復', () {
      final a = ActivityDay(
        date: '2026-11-08',
        totalSteps: 9000,
        walkSteps: 6000,
        walkKcal: 160.5,
        exercises: [
          ExerciseEntry(
            kind: ExerciseKind.running,
            title: '朝ラン',
            start: t(7),
            end: t(7, 30),
            kcal: 300,
            estimated: false,
            origins: const ['com.strava'],
          ),
        ],
        syncedAt: t(9),
      );
      final b = ActivityDay.fromDbMap(a.toDbMap());
      expect(b.totalSteps, 9000);
      expect(b.walkSteps, 6000);
      expect(b.exercises.single.displayName, '朝ラン');
      expect(b.exercises.single.duration, const Duration(minutes: 30));
      expect(b.totalKcal, closeTo(460.5, 0.01));
    });

    test('古い体重データ（source 列なし）は手入力扱い', () {
      final w = WeightEntry.fromDbMap({'date': '2026-11-08', 'weight_kg': 70.2});
      expect(w.isAuto, isFalse);
      expect(w.bodyFatPct, isNull);
    });

    test('アプリ名の表示', () {
      expect(originLabel('com.strava'), 'Strava');
      expect(originLabel('com.example.inbodyapp'), 'InBody');
      expect(originLabel('com.foo'), 'com.foo');
    });
  });
}
