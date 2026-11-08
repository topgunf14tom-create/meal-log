import 'package:flutter_test/flutter_test.dart';
import 'package:meal_log/core/alcohol.dart';

Drink byName(String n) => drinks.firstWhere((d) => d.name == n);

void main() {
  group('お酒のカロリー', () {
    test('ビール350ml缶：純アルコール14g・約146kcal', () {
      final beer = byName('ビール');
      expect(beer.alcoholG(350), closeTo(14.0, 1e-9));
      expect(beer.kcal(350).round(), 146);
    });

    test('ハイボール1杯（ウイスキー30ml）は糖質0・約67kcal', () {
      final hb = byName('ハイボール');
      final item = hb.toItem(hb.sizes.first, 1);
      expect(item.kcal, 67);
      expect(item.carbs, 0);
      expect(item.fat, 0);
      expect(item.unit, '杯');
      expect(item.sourceType, 'reference');
    });

    test('日本酒1合は約189kcal、赤ワイングラスは約89kcal', () {
      expect(byName('日本酒').kcal(180).round(), 189);
      expect(byName('赤ワイン').kcal(120).round(), 89);
    });

    test('杯数ぶん量・カロリーが増える', () {
      final beer = byName('ビール');
      final size = beer.sizes.firstWhere((s) => s.label == '中ジョッキ');
      final one = beer.toItem(size, 1);
      final two = beer.toItem(size, 2);
      expect(two.grams, 700);
      expect(two.amount, 2);
      expect(two.kcal, closeTo(one.kcal * 2, 1));
      expect(two.name, 'ビール（中ジョッキ）');
    });

    test('その他のお酒', () {
      final d = customDrink('マッコリ', 6, 2);
      // 300ml：純アルコール14.4g×7＋糖質6g×4
      expect(d.kcal(300), closeTo(14.4 * 7 + 24, 1e-9));
      expect(customDrink('  ', 5, 0).name, 'お酒');
    });

    test('全てのお酒にサイズがある', () {
      for (final d in drinks) {
        expect(d.sizes, isNotEmpty, reason: d.name);
      }
    });
  });
}
