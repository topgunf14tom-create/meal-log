import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;

import '../core/food_db.dart';
import '../data/app_db.dart';
import '../data/entities.dart';

/// 同梱の食品DB＋個人DB＋利用履歴。起動時に裏で読み込み、検索は端末内で完結する
class FoodRepository {
  FoodRepository(this._db);

  final AppDb _db;
  FoodDb _food = FoodDb();
  Future<FoodDb>? _loading;

  /// food_ref → 前回選んだ量感クラス
  final Map<String, int> lastClass = {};

  static const assetDir = 'assets/fooddb';

  /// 読み込み完了を待って DB を返す（2回目以降はすぐ返る）
  Future<FoodDb> get ready => _loading ??= _load();

  /// 読み込み済みなら DB、まだなら空
  FoodDb get current => _food;

  Future<FoodDb> _load() async {
    final texts = await Future.wait([
      rootBundle.loadString('$assetDir/fooddb_seibunhyou.json'),
      rootBundle.loadString('$assetDir/fooddb_chains.json'),
      rootBundle.loadString('$assetDir/fooddb_izakaya.json'),
      rootBundle.loadString('$assetDir/fooddb_breakfast.json'),
    ]);
    final food = await compute(_buildFromTexts, texts);
    for (final u in await _db.userFoods()) {
      food.add(userFoodRecord(u));
    }
    final usage = await _db.foodUsage();
    usage.forEach((ref, v) {
      food.usage[ref] = v.count;
      if (v.lastClass != null) lastClass[ref] = v.lastClass!;
    });
    _food = food;
    return food;
  }

  /// 個人DBの1件を検索用のレコードにする
  static FoodRecord userFoodRecord(UserFood u) => FoodRecord(
        ref: 'u:${u.id}',
        source: FoodSource.personal,
        name: u.name,
        kcal: u.kcal,
        protein: u.protein,
        fat: u.fat,
        carbs: u.carbs,
        salt: u.salt,
        per100g: u.per100g,
        servingGrams: u.grams,
        servingLabel: u.per100g ? '100g' : u.unitLabel,
        estimated: u.estimated,
        jan: u.jan,
      );

  Future<FoodRecord> saveUserFood(UserFood u) async {
    final id = await _db.saveUserFood(u);
    final rec = userFoodRecord(UserFood(
      id: id,
      name: u.name,
      jan: u.jan,
      kcal: u.kcal,
      protein: u.protein,
      fat: u.fat,
      carbs: u.carbs,
      salt: u.salt,
      unitLabel: u.unitLabel,
      grams: u.grams,
      per100g: u.per100g,
      estimated: u.estimated,
    ));
    (await ready).add(rec);
    return rec;
  }

  Future<void> deleteUserFood(int id) async {
    await _db.deleteUserFood(id);
    (await ready).removeRef('u:$id');
  }

  /// 記録した品目の利用回数と量感クラスを覚える（候補の並び・次回の初期値に使う）
  Future<void> recordUsage(Iterable<MealItem> items) async {
    final food = await ready;
    for (final i in items) {
      final ref = i.foodRef;
      if (ref == null) continue;
      await _db.bumpFoodUsage(ref, i.sizeClass);
      food.usage[ref] = (food.usage[ref] ?? 0) + 1;
      if (i.sizeClass != null) lastClass[ref] = i.sizeClass!;
    }
  }
}

FoodDb _buildFromTexts(List<String> t) =>
    buildFoodDb(seibunJson: t[0], chainsJson: t[1], izakayaJson: t[2], breakfastJson: t[3]);
