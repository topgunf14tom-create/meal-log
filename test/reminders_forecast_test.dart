import 'package:flutter_test/flutter_test.dart';
import 'package:meal_log/core/forecast.dart';
import 'package:meal_log/core/meal_type.dart';
import 'package:meal_log/core/reminders.dart';

void main() {
  group('記録忘れの通知', () {
    test('時刻の読み書き', () {
      expect(parseHm('9:30'), 570);
      expect(parseHm('21:05'), 21 * 60 + 5);
      expect(parseHm('25:00'), isNull);
      expect(parseHm('abc'), isNull);
      expect(formatHm(570), '9:30');
    });

    test('今日の記録済み・過ぎた時刻は通知しない', () {
      final now = DateTime(2026, 11, 9, 12, 0);
      final plans = planReminders(
        now: now,
        minutes: defaultReminderMinutes,
        recordedToday: {MealType.lunch},
        days: 2,
      );
      // 今日：朝食は過ぎた、昼食は記録済み → 夕食のみ。明日：3件
      expect(plans.length, 4);
      expect(plans.first.type, MealType.dinner);
      expect(plans.first.at, DateTime(2026, 11, 9, 20, 30));
      expect(plans[1].at, DateTime(2026, 11, 10, 9, 30));
      expect(plans.map((p) => p.id).toSet().length, 4);
      expect(plans.first.title, '夕食の記録がまだです');
    });

    test('時刻を消した食事は通知しない', () {
      final plans = planReminders(
        now: DateTime(2026, 11, 9, 5),
        minutes: {MealType.dinner: 20 * 60},
        recordedToday: const {},
        days: 1,
      );
      expect(plans.length, 1);
      expect(plans.single.type, MealType.dinner);
    });
  });

  group('体重の見込み', () {
    test('摂取と消費の差から30日後', () {
      final days = [
        for (var i = 0; i < 14; i++)
          BalanceDay(date: DateTime(2026, 11, 1 + i), intakeKcal: i == 3 ? 0 : 1800, activityKcal: 300),
      ];
      final f = forecastWeight(days: days, bmrFromInBody: 1600, weightKg: 65)!;
      expect(f.days, 13);
      expect(f.avgBurn, closeTo(1600 * 1.1 + 300, 1e-9));
      expect(f.avgBalance, closeTo(1800 - 2060, 1e-9));
      expect(f.kgPer30Days, closeTo(-260 * 30 / 7200, 1e-9));
      expect(f.bmrEstimated, isFalse);
    });

    test('InBody が無ければ体重から基礎代謝を推定', () {
      final days = [
        BalanceDay(date: DateTime(2026, 11, 1), intakeKcal: 2000, activityKcal: 0),
        BalanceDay(date: DateTime(2026, 11, 2), intakeKcal: 2000, activityKcal: 0),
      ];
      final f = forecastWeight(days: days, bmrFromInBody: null, weightKg: 70)!;
      expect(f.bmr, 70 * 22);
      expect(f.bmrEstimated, isTrue);
    });

    test('記録が1日だけなら出さない', () {
      expect(
        forecastWeight(days: [BalanceDay(date: DateTime(2026), intakeKcal: 2000, activityKcal: 0)], bmrFromInBody: 1500, weightKg: 60),
        isNull,
      );
    });

    test('体重の推移の傾き', () {
      final w = [for (var i = 0; i <= 10; i++) (DateTime(2026, 11, 1 + i), 70 - i * 0.1)];
      expect(weightTrendPer30Days(w), closeTo(-3, 1e-6));
      expect(weightTrendPer30Days(w.take(2).toList()), isNull);
      expect(weightTrendPer30Days(w.take(4).toList()), isNull); // 期間が7日未満
    });
  });
}
