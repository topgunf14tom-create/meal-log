/// 量の決め方（量感クラス × 基準量）と栄養計算。計算はすべてコード側で決定的に行う（同じ入力 → 同じ結果）。
library;

import 'dart:math' as math;

import 'food_db.dart';

/// 量感クラス（モデル出力・保存では数値コード 0〜3）
const sizeClassLabels = ['少なめ', '普通', '多め', '大盛'];
const sizeClassFactors = [0.7, 1.0, 1.3, 1.6];
const sizeNormal = 1;

/// 0〜3 に収める
int clampClass(int? c) {
  final v = c ?? sizeNormal;
  if (v < 0) return 0;
  if (v > 3) return 3;
  return v;
}

double sizeFactor(int? c) => sizeClassFactors[clampClass(c)];

/// 料理のカテゴリ（基準量を決める。モデル出力では数値コード）
enum DishCategory { rice, noodle, bread, soup, main, side, fruit, drink, sweets, other }

extension DishCategoryX on DishCategory {
  String get label => const ['ごはん', '麺', 'パン', '汁物', '主菜', '副菜', '果物', '飲み物', '菓子', 'その他'][index];

  /// 「普通」の基準量（g）。実装時の初期値（§6.1）
  double get baseGrams => const [180.0, 220.0, 60.0, 180.0, 100.0, 70.0, 100.0, 200.0, 50.0, 100.0][index];
}

DishCategory dishCategoryFromCode(Object? v) {
  final i = (v is num) ? v.toInt() : int.tryParse('$v');
  if (i == null || i < 0 || i >= DishCategory.values.length) return DishCategory.other;
  return DishCategory.values[i];
}

/// 成分表の食品から推定するカテゴリ（モデルの判定が無いときの補助）
DishCategory guessCategory(FoodRecord f) {
  final n = f.name;
  final g = f.group ?? '';
  if (RegExp(r'めし|おにぎり|粥|赤飯|ピラフ|チャーハン').hasMatch(n)) return DishCategory.rice;
  if (RegExp(r'めん|うどん|そば|そうめん|スパゲッティ|パスタ|ビーフン').hasMatch(n)) return DishCategory.noodle;
  if (RegExp(r'パン').hasMatch(n)) return DishCategory.bread;
  if (RegExp(r'汁|スープ').hasMatch(n)) return DishCategory.soup;
  if (g.contains('果実')) return DishCategory.fruit;
  if (g.contains('し好飲料') || RegExp(r'牛乳|液状乳|飲料|ジュース').hasMatch(n)) return DishCategory.drink;
  if (g.contains('菓子')) return DishCategory.sweets;
  if (RegExp(r'魚介|肉|卵').hasMatch(g)) return DishCategory.main;
  if (RegExp(r'野菜|きのこ|藻|いも|豆').hasMatch(g)) return DishCategory.side;
  if (g.contains('調理済み')) return DishCategory.main;
  return DishCategory.other;
}

/// 調理法（見えない油・調味料の定型値をコード側で加算する。モデルには推測させない）
enum CookMethod { none, stirFry, deepFry, simmered, grilled, dressed }

class CookAddon {
  const CookAddon(this.label, this.kcal, this.p, this.f, this.c);

  final String label;
  final double kcal;
  final double p;
  final double f;
  final double c;
}

extension CookMethodX on CookMethod {
  String get label => const ['なし', '炒め物', '揚げ物', '煮物', '焼き物', '和え物・サラダ'][index];

  /// 「普通」1人前あたりの加算値（成分表：調合油 886kcal/100g、上白糖 391kcal/100g、ドレッシング類から概算）
  CookAddon? get addon => switch (this) {
        CookMethod.none => null,
        CookMethod.stirFry => const CookAddon('炒め油 大さじ1（12g）', 106, 0, 12, 0),
        CookMethod.deepFry => const CookAddon('揚げ油の吸油 約10g', 89, 0, 10, 0),
        CookMethod.simmered => const CookAddon('砂糖 小さじ2（6g）', 23, 0, 0, 6),
        CookMethod.grilled => const CookAddon('油 小さじ1（4g）', 35, 0, 4, 0),
        CookMethod.dressed => const CookAddon('ドレッシング 大さじ1（15g）', 50, 0.2, 4.5, 2.1),
      };
}

CookMethod cookMethodFromCode(Object? v) {
  final i = (v is num) ? v.toInt() : int.tryParse('$v');
  if (i == null || i < 0 || i >= CookMethod.values.length) return CookMethod.none;
  return CookMethod.values[i];
}

/// 取り分け・残しのプリセット（食べた割合）
const ratioPresets = <(String, double)>[
  ('全部', 1.0),
  ('3/4', 0.75),
  ('1/2', 0.5),
  ('1/3', 1 / 3),
  ('1/4', 0.25),
  ('1/5', 0.2),
];

String ratioLabel(double r) {
  for (final p in ratioPresets) {
    if ((p.$2 - r).abs() < 0.001) return p.$1;
  }
  return '${(r * 100).round()}%';
}

/// 1品の量の指定
class Portion {
  const Portion({
    required this.food,
    this.category,
    this.sizeClass = sizeNormal,
    this.count = 1,
    this.ratio = 1,
    this.manualGrams,
    this.cook = CookMethod.none,
    this.pfcFrom,
  });

  final FoodRecord food;

  /// 写真判定のカテゴリ（無ければ食品から推定）
  final DishCategory? category;
  final int sizeClass;

  /// 個数（1食あたりの食品のみ）
  final double count;

  /// 食べた割合（取り分け 1/N・残した分）
  final double ratio;

  /// 計量したグラム数（主食の計量など。入力があればクラスより優先）
  final double? manualGrams;
  final CookMethod cook;

  /// kcal のみ公表の食品の PFC を補完する成分表の類似食品
  final FoodRecord? pfcFrom;

  /// 量感クラスを選べるか（チェーン店は公式のサイズ違いを使うので選ばない）
  bool get usesSizeClass => food.source != FoodSource.chain && food.source != FoodSource.personal;

  /// 個数を選べるか（100gあたりの食品はグラムで決める）
  bool get usesCount => !food.per100g;

  DishCategory get effectiveCategory => category ?? guessCategory(food);

  /// 「普通」の量（g）。100gあたりの食品だけ §6.1 のカテゴリ別基準表を使う。
  /// 1食あたりの食品（チェーン・辞書・登録食品）は「1食 = 普通」とし、クラス係数を掛ける
  double get baseGrams => food.per100g ? effectiveCategory.baseGrams : (food.servingGrams ?? effectiveCategory.baseGrams);

  /// 計量グラムを入力できるか（100gあたりの食品のみ。辞書の重さは材料の合計なので使わない）
  bool get usesManualGrams => food.per100g;

  /// 食品の値に掛ける倍率（100gあたりなら g÷100、1食あたりならクラス係数）
  double get amountFactor {
    if (food.per100g) {
      final g = (manualGrams != null && manualGrams! > 0) ? manualGrams! : baseGrams * sizeFactor(sizeClass);
      return g / 100;
    }
    return usesSizeClass ? sizeFactor(sizeClass) : 1.0;
  }

  Portion copyWith({
    FoodRecord? food,
    DishCategory? category,
    int? sizeClass,
    double? count,
    double? ratio,
    double? manualGrams,
    bool clearManualGrams = false,
    CookMethod? cook,
    FoodRecord? pfcFrom,
    bool clearPfcFrom = false,
  }) =>
      Portion(
        food: food ?? this.food,
        category: category ?? this.category,
        sizeClass: sizeClass ?? this.sizeClass,
        count: count ?? this.count,
        ratio: ratio ?? this.ratio,
        manualGrams: clearManualGrams ? null : (manualGrams ?? this.manualGrams),
        cook: cook ?? this.cook,
        pfcFrom: clearPfcFrom ? null : (pfcFrom ?? this.pfcFrom),
      );
}

/// 計算結果（丸め済み：kcal 整数、PFC・塩分は小数1桁）
class PortionResult {
  const PortionResult({
    required this.kcal,
    required this.protein,
    required this.fat,
    required this.carbs,
    this.salt,
    this.grams,
    required this.pfcUnknown,
    required this.notes,
  });

  final double kcal;
  final double protein;
  final double fat;
  final double carbs;
  final double? salt;
  final double? grams;

  /// PFC 不明（kcal のみ公表で補完しなかった）
  final bool pfcUnknown;

  /// 計算の内訳（「炒め油 大さじ1」「1/3 取り分け」「PFCは○○で補完」など）
  final List<String> notes;
}

double round1(double v) => (v * 10).roundToDouble() / 10;

/// 栄養計算：成分表は 100gあたり値 × g ÷ 100、1食値はそのまま × 個数。最後に食べた割合を掛ける
PortionResult computePortion(Portion p) {
  final f = p.food;
  final amount = p.amountFactor * (p.usesCount ? p.count : 1) * p.ratio;
  final kcal = (f.kcal ?? 0) * amount;
  double prot;
  double fat;
  double carbs;
  var unknown = false;
  final notes = <String>[];

  if (!f.pfcUnknown) {
    prot = f.protein! * amount;
    fat = f.fat! * amount;
    carbs = f.carbs! * amount;
  } else if (p.pfcFrom != null && (p.pfcFrom!.kcal ?? 0) > 0 && !p.pfcFrom!.pfcUnknown) {
    // kcal は公式値のまま、PFC の比率だけ類似食品から借りる
    final s = p.pfcFrom!;
    final k = kcal / s.kcal!;
    prot = s.protein! * k;
    fat = s.fat! * k;
    carbs = s.carbs! * k;
    notes.add('PFCは成分表「${s.name}」の比率で補完（推定）');
  } else {
    prot = 0;
    fat = 0;
    carbs = 0;
    unknown = true;
    notes.add('PFC不明（公式はkcalのみ公表）');
  }

  var addK = 0.0, addP = 0.0, addF = 0.0, addC = 0.0;
  final addon = p.cook.addon;
  if (addon != null && !f.alreadyCooked) {
    final m = (p.usesSizeClass ? sizeFactor(p.sizeClass) : 1.0) * p.ratio;
    addK = addon.kcal * m;
    addP = addon.p * m;
    addF = addon.f * m;
    addC = addon.c * m;
    notes.add('＋${addon.label}');
  }

  double? grams;
  if (f.per100g) {
    grams = p.amountFactor * 100 * p.ratio;
  } else if (f.servingGrams != null) {
    grams = f.servingGrams! * p.amountFactor * p.count * p.ratio;
  }
  if (p.ratio != 1) notes.add('食べた割合 ${ratioLabel(p.ratio)}');

  return PortionResult(
    kcal: (kcal + addK).roundToDouble(),
    protein: round1(prot + addP),
    fat: round1(fat + addF),
    carbs: round1(carbs + addC),
    salt: f.salt == null ? null : round1(f.salt! * amount),
    grams: grams == null ? null : round1(grams),
    pfcUnknown: unknown,
    notes: notes,
  );
}

/// 量の表示（例「普通（180g）」「2個」「1/3」）
String portionAmountText(Portion p, PortionResult r) {
  final parts = <String>[];
  if (p.manualGrams != null && p.usesManualGrams) {
    parts.add('計量 ${p.manualGrams!.round()}g');
  } else if (p.usesSizeClass) {
    parts.add(sizeClassLabels[clampClass(p.sizeClass)]);
  }
  if (p.usesCount && p.count != 1) parts.add('×${_n(p.count)}');
  if (r.grams != null) parts.add('${r.grams!.round()}g');
  return parts.join(' ');
}

String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// Atwater 係数による整合性チェック：kcal ≒ P×4 + F×9 + C×4
/// 乖離が max(20kcal, 15%) 以内なら true
bool atwaterOk(double kcal, double p, double f, double c, {double tolerance = 0.15, double minKcal = 20}) {
  final est = p * 4 + f * 9 + c * 4;
  final diff = (kcal - est).abs();
  final allowed = math.max(minKcal, kcal * tolerance);
  return diff <= allowed;
}
