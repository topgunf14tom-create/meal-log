import 'package:flutter_test/flutter_test.dart';
import 'package:meal_log/core/meal_type.dart';
import 'package:meal_log/core/nutrition.dart';
import 'package:meal_log/core/pricing.dart';
import 'package:meal_log/core/text_normalize.dart';
import 'package:meal_log/data/entities.dart';

void main() {
  group('PFC計算', () {
    test('目標グラム', () {
      const g = Goal(startDate: '2026-09-28', targetKcal: 2000, pRatio: 20, fRatio: 25, cRatio: 55);
      final t = targetGrams(g);
      expect(t.p, closeTo(100, 0.01));
      expect(t.f, closeTo(55.56, 0.01));
      expect(t.c, closeTo(275, 0.01));
    });

    test('エネルギー比率', () {
      const p = Pfc(0, 25, 10, 50); // 100 + 90 + 200 = 390 kcal
      final r = p.energyRatio();
      expect(r.p, closeTo(25.64, 0.01));
      expect(r.f, closeTo(23.08, 0.01));
      expect(r.c, closeTo(51.28, 0.01));
      expect(r.p + r.f + r.c, closeTo(100, 0.001));
    });

    test('ゼロのときは0%', () {
      final r = Pfc.zero.energyRatio();
      expect(r.p, 0);
      expect(r.f, 0);
      expect(r.c, 0);
    });

    test('合計と量の按分', () {
      const a = MealItem(name: 'A', amount: 1, grams: 200, kcal: 300, protein: 10, fat: 5, carbs: 50);
      const b = MealItem(name: 'B', kcal: 100, protein: 2, fat: 1, carbs: 20);
      final sum = Pfc.sum([a, b]);
      expect(sum.kcal, 400);
      expect(sum.p, 12);

      final half = a.scaled(0.5);
      expect(half.amount, 0.5);
      expect(half.grams, 100);
      expect(half.kcal, 150);
      expect(half.carbs, 25);
    });
  });

  group('料金計算', () {
    const table = PriceTable();

    test('Haiku 写真1枚', () {
      final usd = table.costUsd('claude-haiku-4-5-20251001', 2100, 500, 0);
      expect(usd, closeTo(0.0046, 1e-9));
    });

    test('Sonnet + Web検索', () {
      final usd = table.costUsd('claude-sonnet-5', 10000, 600, 1);
      expect(usd, closeTo(0.02 + 0.006 + 0.01, 1e-9));
    });
  });

  group('キャッシュキー正規化', () {
    test('全角英数・空白・大文字を統一', () {
      expect(normalizeKey('ＢＩＧ　Ｍａｃ'), 'bigmac');
      expect(normalizeKey(' 牛丼 並盛 '), '牛丼並盛');
      expect(normalizeKey('吉野家'), normalizeKey('吉野家　'));
    });
  });

  group('食事区分の推定', () {
    test('時刻から推定', () {
      expect(guessMealType(DateTime(2026, 1, 1, 7)), MealType.breakfast);
      expect(guessMealType(DateTime(2026, 1, 1, 12)), MealType.lunch);
      expect(guessMealType(DateTime(2026, 1, 1, 19)), MealType.dinner);
      expect(guessMealType(DateTime(2026, 1, 1, 16)), MealType.snack);
    });
  });
}
