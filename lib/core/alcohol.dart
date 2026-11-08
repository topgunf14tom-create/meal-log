import '../data/entities.dart';

/// お酒のカロリーは「純アルコール量×7kcal＋糖質×4＋タンパク質×4」で計算する。
/// 度数・糖質は日本食品標準成分表（八訂）と一般的な商品の値を参考にした目安。
/// アルコールのエネルギーは PFC に含まれないため、kcal は PFC からの計算値より大きくなる。

/// 純アルコール1gあたりのエネルギー（kcal）
const alcoholKcalPerGram = 7.0;

/// エタノールの比重
const ethanolDensity = 0.8;

/// 1日の節度ある飲酒の目安（純アルコール g、厚生労働省）
const dailyAlcoholGuideG = 20.0;

class DrinkSize {
  const DrinkSize(this.label, this.ml, this.unit);

  final String label;

  /// 量（ml）。割り物は「お酒そのもの」の量
  final double ml;

  /// 数える単位（缶・杯・本・合）
  final String unit;
}

class Drink {
  const Drink({
    required this.name,
    required this.abv,
    this.carbsPer100 = 0,
    this.proteinPer100 = 0,
    required this.sizes,
    this.note,
  });

  final String name;

  /// アルコール度数（%）
  final double abv;

  /// 100ml あたりの糖質（炭水化物）g
  final double carbsPer100;

  /// 100ml あたりのタンパク質 g
  final double proteinPer100;
  final List<DrinkSize> sizes;
  final String? note;

  double alcoholG(double ml) => ml * abv / 100 * ethanolDensity;
  double carbsG(double ml) => ml * carbsPer100 / 100;
  double proteinG(double ml) => ml * proteinPer100 / 100;
  double kcal(double ml) => alcoholG(ml) * alcoholKcalPerGram + carbsG(ml) * 4 + proteinG(ml) * 4;

  /// 記録用の料理1品にする
  MealItem toItem(DrinkSize size, double count) {
    final ml = size.ml * count;
    return MealItem(
      name: '$name（${size.label}）',
      amount: count,
      unit: size.unit,
      grams: ml,
      kcal: kcal(ml).roundToDouble(),
      protein: double.parse(proteinG(ml).toStringAsFixed(1)),
      fat: 0,
      carbs: double.parse(carbsG(ml).toStringAsFixed(1)),
      confidence: 'medium',
      sourceType: 'reference',
    );
  }
}

const _can = [DrinkSize('350ml缶', 350, '缶'), DrinkSize('500ml缶', 500, '缶')];

const drinks = <Drink>[
  Drink(
    name: 'ビール',
    abv: 5,
    carbsPer100: 3.1,
    proteinPer100: 0.3,
    sizes: [
      DrinkSize('350ml缶', 350, '缶'),
      DrinkSize('500ml缶', 500, '缶'),
      DrinkSize('中ジョッキ', 350, '杯'),
      DrinkSize('グラス', 200, '杯'),
      DrinkSize('中瓶', 500, '本'),
      DrinkSize('大瓶', 633, '本'),
    ],
  ),
  Drink(name: '発泡酒・新ジャンル', abv: 5.5, carbsPer100: 3.6, proteinPer100: 0.1, sizes: _can),
  Drink(name: '糖質オフ・ゼロのビール系', abv: 4.5, carbsPer100: 0.5, sizes: _can),
  Drink(
    name: 'ハイボール',
    abv: 40,
    note: 'ウイスキーの量で計算（炭酸は0kcal）',
    sizes: [
      DrinkSize('1杯 ウイスキー30ml', 30, '杯'),
      DrinkSize('濃いめ 45ml', 45, '杯'),
      DrinkSize('メガ 60ml', 60, '杯'),
    ],
  ),
  Drink(name: 'ハイボール缶（7%）', abv: 7, sizes: _can),
  Drink(
    name: 'レモンサワー・チューハイ',
    abv: 5,
    carbsPer100: 3.5,
    sizes: [
      DrinkSize('350ml缶', 350, '缶'),
      DrinkSize('500ml缶', 500, '缶'),
      DrinkSize('居酒屋の1杯', 350, '杯'),
    ],
  ),
  Drink(name: 'ストロング系チューハイ（9%）', abv: 9, carbsPer100: 3.0, sizes: _can),
  Drink(
    name: '赤ワイン',
    abv: 12,
    carbsPer100: 1.5,
    proteinPer100: 0.2,
    sizes: [
      DrinkSize('グラス', 120, '杯'),
      DrinkSize('ハーフボトル', 375, '本'),
      DrinkSize('ボトル', 750, '本'),
    ],
  ),
  Drink(
    name: '白ワイン',
    abv: 11.5,
    carbsPer100: 2.0,
    proteinPer100: 0.1,
    sizes: [
      DrinkSize('グラス', 120, '杯'),
      DrinkSize('ハーフボトル', 375, '本'),
      DrinkSize('ボトル', 750, '本'),
    ],
  ),
  Drink(
    name: 'スパークリングワイン',
    abv: 11.5,
    carbsPer100: 3.0,
    sizes: [DrinkSize('グラス', 120, '杯'), DrinkSize('ボトル', 750, '本')],
  ),
  Drink(
    name: '日本酒',
    abv: 15,
    carbsPer100: 4.9,
    proteinPer100: 0.4,
    sizes: [
      DrinkSize('1合', 180, '合'),
      DrinkSize('グラス', 120, '杯'),
      DrinkSize('おちょこ', 30, '杯'),
    ],
  ),
  Drink(
    name: '焼酎（ロック・水割り・お湯割り）',
    abv: 25,
    note: '焼酎の量で計算',
    sizes: [DrinkSize('1杯 焼酎60ml', 60, '杯'), DrinkSize('ダブル 90ml', 90, '杯')],
  ),
  Drink(
    name: 'ウイスキー（ロック・ストレート）',
    abv: 40,
    sizes: [DrinkSize('シングル 30ml', 30, '杯'), DrinkSize('ダブル 60ml', 60, '杯')],
  ),
  Drink(
    name: '梅酒',
    abv: 13,
    carbsPer100: 20.7,
    proteinPer100: 0.1,
    note: '梅酒の量で計算',
    sizes: [DrinkSize('ロック 60ml', 60, '杯'), DrinkSize('多め 90ml', 90, '杯')],
  ),
  Drink(
    name: '甘いカクテル',
    abv: 4.5,
    carbsPer100: 15,
    note: 'カシスオレンジ・ファジーネーブルなど',
    sizes: [DrinkSize('1杯', 200, '杯')],
  ),
  Drink(
    name: 'ジン・ウォッカのソーダ割り',
    abv: 40,
    note: 'スピリッツの量で計算。トニック割りは糖質が加わります',
    sizes: [DrinkSize('1杯 30ml', 30, '杯'), DrinkSize('濃いめ 45ml', 45, '杯')],
  ),
];

/// 度数と量を自分で入れる「その他のお酒」
Drink customDrink(String name, double abv, double carbsPer100) => Drink(
      name: name.trim().isEmpty ? 'お酒' : name.trim(),
      abv: abv,
      carbsPer100: carbsPer100,
      sizes: const [],
    );
