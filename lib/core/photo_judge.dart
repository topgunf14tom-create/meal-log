/// 写真判定（Haiku）の出力。料理名候補・量感クラス・寸法だけで、栄養数値は含まない。
library;

import 'dart:convert';

import 'portion.dart';

/// 1品分の判定
class JudgedDish {
  const JudgedDish({
    required this.name,
    this.candidates = const [],
    this.category = DishCategory.other,
    this.sizeClass = sizeNormal,
    this.grams,
    this.cook = CookMethod.none,
    this.footprintCm,
    this.heightCm,
    this.confidence = 0.5,
  });

  final String name;
  final List<String> candidates;
  final DishCategory category;
  final int sizeClass;

  /// 補助情報（最終的なグラム数は基準量 × クラス係数で決める）
  final double? grams;
  final CookMethod cook;
  final List<double>? footprintCm;
  final double? heightCm;

  /// 0〜1。0.5 未満は記録前の確認を必須にする
  final double confidence;

  bool get needsConfirm => confidence < 0.5;

  /// 照合に使う名前（料理名 → 候補の順、重複なし）
  List<String> get lookupNames => {name, ...candidates}.where((s) => s.trim().isNotEmpty).toList();

  Map<String, dynamic> toCompactJson() => {
        'n': name,
        if (candidates.isNotEmpty) 'c': candidates,
        't': category.index,
        's': sizeClass,
        if (grams != null) 'g': grams!.round(),
        'k': cook.index,
        if (footprintCm != null) 'w': footprintCm!.map((e) => e.round()).toList(),
        if (heightCm != null) 'h': heightCm!.round(),
        'p': confidence,
      };
}

class PhotoJudgement {
  const PhotoJudgement(this.dishes, {this.plateCm, this.note});

  final List<JudgedDish> dishes;

  /// 推定した皿の直径
  final double? plateCm;
  final String? note;

  String toCompactString() => jsonEncode({
        if (plateCm != null) 'd': plateCm!.round(),
        'i': dishes.map((d) => d.toCompactJson()).toList(),
        if (note != null) 'm': note,
      });
}

/// 栄養数値として扱わないキー（もし出力されても読まない）
const forbiddenNutritionKeys = {'kcal', 'protein', 'protein_g', 'fat', 'fat_g', 'carbs', 'carbs_g', 'energy'};

double? _num(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int _cls(Object? v) {
  if (v is num) return clampClass(v.toInt());
  // 念のため日本語ラベルも受け付ける
  final i = sizeClassLabels.indexOf('$v');
  return i >= 0 ? i : sizeNormal;
}

/// モデル出力（短いキーの JSON）を読む。前置きやコードブロックが付いていても { … } を取り出す
PhotoJudgement parsePhotoJudgement(String raw) {
  final text = raw.trim();
  Object? decoded = _tryDecode(text);
  if (decoded is! Map) {
    final s = text.indexOf('{');
    final e = text.lastIndexOf('}');
    if (s >= 0 && e > s) decoded = _tryDecode(text.substring(s, e + 1));
  }
  if (decoded is! Map) throw const FormatException('判定結果（JSON）を読み取れませんでした');

  final list = decoded['i'] ?? decoded['items'];
  final dishes = <JudgedDish>[];
  if (list is List) {
    for (final e in list.whereType<Map>()) {
      final name = (e['n'] ?? e['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final cands = e['c'] ?? e['candidates'];
      final w = e['w'] ?? e['footprint_cm'];
      final conf = _num(e['p'] ?? e['confidence']) ?? 0.5;
      dishes.add(JudgedDish(
        name: name,
        candidates: cands is List ? cands.map((x) => x.toString().trim()).where((x) => x.isNotEmpty).toList() : const [],
        category: dishCategoryFromCode(e['t']),
        sizeClass: _cls(e['s'] ?? e['size_class']),
        grams: _num(e['g'] ?? e['estimated_grams']),
        cook: cookMethodFromCode(e['k']),
        footprintCm: w is List ? w.map(_num).whereType<double>().toList() : null,
        heightCm: _num(e['h'] ?? e['height_cm']),
        confidence: conf > 1 ? conf / 100 : conf,
      ));
    }
  }
  final note = decoded['m']?.toString().trim();
  return PhotoJudgement(
    dishes,
    plateCm: _num(decoded['d']),
    note: (note == null || note.isEmpty || note == 'null') ? null : note,
  );
}

Object? _tryDecode(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}
