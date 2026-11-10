import 'package:flutter_test/flutter_test.dart';
import 'package:meal_log/core/food_db.dart';
import 'package:meal_log/core/image_hash.dart';
import 'package:meal_log/core/label_text.dart';
import 'package:meal_log/core/photo_judge.dart';
import 'package:meal_log/core/portion.dart';
import 'package:meal_log/core/dates.dart';

FoodRecord _rice() => FoodRecord(
      ref: 's:1088',
      source: FoodSource.seibun,
      name: 'こめ ［水稲めし］ 精白米 うるち米',
      group: '穀類',
      kcal: 156,
      protein: 2.5,
      fat: 0.3,
      carbs: 37.1,
      per100g: true,
    );

FoodRecord _pork() => FoodRecord(
      ref: 's:11123',
      source: FoodSource.seibun,
      name: 'ぶた ［大型種肉］ ロース 脂身つき 生',
      group: '肉類',
      kcal: 248,
      protein: 19.3,
      fat: 19.2,
      carbs: 0.2,
      per100g: true,
    );

FoodRecord _gyudon() => FoodRecord(
      ref: 'c:すき家:牛丼:並盛',
      source: FoodSource.chain,
      name: '牛丼',
      chain: 'すき家',
      variant: '並盛',
      kcal: 733,
      protein: 22.9,
      fat: 25.0,
      carbs: 104.1,
      salt: 2.6,
    );

FoodRecord _sushi() => FoodRecord(
      ref: 'c:はま寿司:まぐろ:',
      source: FoodSource.chain,
      name: 'まぐろ',
      chain: 'はま寿司',
      kcal: 80,
    );

void main() {
  group('量感クラス', () {
    test('係数 0.7 / 1.0 / 1.3 / 1.6、ごはんの基準180g', () {
      final grams = [for (var c = 0; c < 4; c++) computePortion(Portion(food: _rice(), category: DishCategory.rice, sizeClass: c)).grams];
      expect(grams, [126, 180, 234, 288]);
    });

    test('計量グラムがあればクラスより優先', () {
      final r = computePortion(Portion(food: _rice(), category: DishCategory.rice, sizeClass: 3, manualGrams: 150));
      expect(r.grams, 150);
      expect(r.kcal, 234);
    });

    test('丸め：kcal整数、PFC小数1桁', () {
      final r = computePortion(Portion(food: _rice(), category: DishCategory.rice));
      expect(r.kcal, 281); // 156×1.8=280.8
      expect(r.protein, 4.5);
      expect(r.carbs, 66.8);
    });

    test('同じ入力なら毎回同じ結果', () {
      final p = Portion(food: _pork(), category: DishCategory.main, sizeClass: 2, cook: CookMethod.stirFry, ratio: 1 / 3);
      final a = computePortion(p);
      final b = computePortion(p);
      expect([a.kcal, a.protein, a.fat, a.carbs], [b.kcal, b.protein, b.fat, b.carbs]);
    });
  });

  group('チェーン・取り分け・調理法', () {
    test('チェーンは公式の1食値をそのまま（クラス係数なし）×個数', () {
      final r = computePortion(Portion(food: _gyudon(), sizeClass: 3, count: 2));
      expect(r.kcal, 1466);
      expect(r.salt, 5.2);
    });

    test('取り分け 1/3', () {
      final r = computePortion(Portion(food: _gyudon(), ratio: 1 / 3));
      expect(r.kcal, 244);
      expect(r.notes.last, contains('1/3'));
    });

    test('炒め物は油大さじ1をコードで加算（生の食材のみ）', () {
      final plain = computePortion(Portion(food: _pork(), category: DishCategory.main));
      final fried = computePortion(Portion(food: _pork(), category: DishCategory.main, cook: CookMethod.stirFry));
      expect(fried.kcal - plain.kcal, 106);
      expect(fried.fat - plain.fat, closeTo(12, 0.05));
      // 成分表で「めし」など調理済みの食品には足さない
      final rice = computePortion(Portion(food: _rice(), category: DishCategory.rice, cook: CookMethod.stirFry));
      expect(rice.kcal, 281);
    });

    test('kcalのみ公表：補完しなければ PFC不明', () {
      final r = computePortion(Portion(food: _sushi()));
      expect(r.kcal, 80);
      expect(r.pfcUnknown, isTrue);
      expect([r.protein, r.fat, r.carbs], [0, 0, 0]);
    });

    test('kcalのみ公表：類似食品の比率で補完（kcalは公式値のまま）', () {
      final tuna = FoodRecord(
        ref: 's:10253',
        source: FoodSource.seibun,
        name: 'まぐろ 赤身 生',
        kcal: 115,
        protein: 26.4,
        fat: 1.4,
        carbs: 0.1,
        per100g: true,
      );
      final r = computePortion(Portion(food: _sushi(), pfcFrom: tuna));
      expect(r.kcal, 80);
      expect(r.pfcUnknown, isFalse);
      expect(r.protein, 18.4); // 26.4 × 80/115
    });
  });

  group('写真判定の出力', () {
    test('短いキーのJSONを読む・栄養値は持たない', () {
      final j = parsePhotoJudgement(
          '```json\n{"d":24,"i":[{"n":"ごはん","c":["ごはん","麦ごはん"],"t":0,"s":2,"g":230,"k":0,"w":[12,12],"h":4,"p":0.8,"kcal":999}]}\n```');
      expect(j.plateCm, 24);
      final d = j.dishes.single;
      expect(d.name, 'ごはん');
      expect(d.sizeClass, 2);
      expect(d.category, DishCategory.rice);
      expect(d.needsConfirm, isFalse);
      expect(j.toCompactString().contains('kcal'), isFalse);
    });

    test('確からしさ0.5未満は要確認', () {
      final j = parsePhotoJudgement('{"i":[{"n":"煮物","s":1,"p":0.3}]}');
      expect(j.dishes.single.needsConfirm, isTrue);
    });
  });

  group('栄養成分表示', () {
    test('OCR文字列から読み取り、整合性チェック', () {
      const text = '栄養成分表示 1袋(45g)当たり\nエネルギー 250kcal\nたんぱく質 3.1g\n脂質 14.2g\n炭水化物 27.6g\n食塩相当量 0.4g';
      final v = parseLabelText(text);
      expect(v.kcal, 250);
      expect(v.protein, 3.1);
      expect(v.fat, 14.2);
      expect(v.carbs, 27.6);
      expect(v.salt, 0.4);
      expect(v.unitLabel, '1袋');
      expect(v.unitGrams, 45);
      expect(v.consistent, isTrue);
    });

    test('ラベルと値が別の列に読まれた場合', () {
      const text = 'エネルギー\nたんぱく質\n脂質\n炭水化物\n食塩相当量\n180kcal\n6.0g\n7.5g\n22.0g\n1.1g';
      final v = parseLabelText(text);
      expect([v.kcal, v.protein, v.fat, v.carbs], [180, 6.0, 7.5, 22.0]);
      expect(v.consistent, isTrue);
    });

    test('読み違いは整合性チェックで落ちる（Haikuに回す）', () {
      final v = parseLabelText('エネルギー 25kcal たんぱく質 3.1g 脂質 14.2g 炭水化物 27.6g');
      expect(v.consistent, isFalse);
    });

    test('Haiku の転記JSON', () {
      final r = parseLabelJson('{"n":"ポテトチップス","u":"1袋","ug":60,"p100":false,"e":336,"p":2.8,"f":21.6,"c":32.4,"s":0.5,"j":"4901330502881"}');
      expect(r.values.name, 'ポテトチップス');
      expect(r.values.kcal, 336);
      expect(r.jan, '4901330502881');
    });

    test('JANのチェックディジット', () {
      expect(isValidJan('4901330502881'), isTrue);
      expect(isValidJan('4901330502882'), isFalse);
      expect(isValidJan('49123456'), isTrue);
    });
  });

  group('その他', () {
    test('dHash とハミング距離', () {
      final g = [for (var i = 0; i < 72; i++) (i * 37) % 256];
      final h = dHashFromGray(g);
      expect(h.length, 16);
      expect(hammingHex(h, h), 0);
      expect(hammingHex('0000000000000000', '000000000000000f'), 4);
    });

    test('1日の区切り（4時区切りなら深夜2時は前日）', () {
      expect(logicalDay(DateTime(2026, 11, 12, 2, 30), 4), DateTime(2026, 11, 11));
      expect(logicalDay(DateTime(2026, 11, 12, 4, 0), 4), DateTime(2026, 11, 12));
      expect(logicalDay(DateTime(2026, 11, 12, 2, 30), 0), DateTime(2026, 11, 12));
    });

    test('Atwater', () {
      expect(atwaterOk(250, 3.1, 14.2, 27.6), isTrue);
      expect(atwaterOk(100, 20, 20, 20), isFalse);
    });
  });
}
