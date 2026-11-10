import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meal_log/core/food_db.dart';
import 'package:meal_log/core/photo_judge.dart';
import 'package:meal_log/core/photo_match.dart';
import 'package:meal_log/core/portion.dart';
import 'package:meal_log/core/search_text.dart';

FoodDb _load() => buildFoodDb(
      seibunJson: File('assets/fooddb/fooddb_seibunhyou.json').readAsStringSync(),
      chainsJson: File('assets/fooddb/fooddb_chains.json').readAsStringSync(),
      izakayaJson: File('assets/fooddb/fooddb_izakaya.json').readAsStringSync(),
      breakfastJson: File('assets/fooddb/fooddb_breakfast.json').readAsStringSync(),
    );

void main() {
  group('searchKey', () {
    test('カタカナ→ひらがな・全角→半角・記号と空白を除く', () {
      expect(searchKey('ポテト サラダ'), 'ぽてとさらだ');
      expect(searchKey('ＡＢＣ／１２３'), 'abc123');
      expect(searchKey('生ビール（中ジョッキ）'), '生びーる中じょっき');
    });

    test('同義語の展開', () {
      expect(expandSynonyms(searchKey('からあげ')), containsAll(['からあげ', '唐揚げ', 'から揚げ']));
      expect(expandSynonyms(searchKey('ごはん')), contains('ご飯'));
    });
  });

  group('同梱DB', () {
    final db = _load();

    test('件数（成分表2,538・チェーン約1万・辞書52+36）', () {
      expect(db.countOf(FoodSource.seibun), 2538);
      expect(db.countOf(FoodSource.chain), greaterThan(10000));
      expect(db.countOf(FoodSource.izakaya), 52);
      expect(db.countOf(FoodSource.breakfast), 36);
    });

    test('参照キーは重複しない', () {
      final refs = db.all.map((r) => r.ref).toList();
      expect(refs.toSet().length, refs.length);
    });

    test('ひらがなで漢字・カタカナ表記にヒット', () {
      final names = db.search('からあげ').take(10).map((h) => h.food.name).toList();
      expect(names, contains('鶏の唐揚げ'));
      expect(db.search('ぽてさら').first.food.name, 'ポテトサラダ');
      expect(db.search('生中').first.food.name, '生ビール（中ジョッキ）');
    });

    test('完全一致 → 前方一致 → 部分一致の順', () {
      final hits = db.search('枝豆');
      expect(hits.first.tier, 0);
      for (var i = 1; i < hits.length; i++) {
        expect(hits[i].tier, greaterThanOrEqualTo(hits[i - 1].tier));
      }
    });

    test('複数語（店名＋メニュー）', () {
      final hits = db.search('すき家 牛丼');
      expect(hits, isNotEmpty);
      expect(hits.every((h) => h.food.chain == 'すき家'), isTrue);
    });

    test('利用履歴の多い候補が上に来る', () {
      final before = db.search('枝豆').where((h) => h.tier == 0).toList();
      if (before.length >= 2) {
        db.usage[before.last.food.ref] = 99;
        expect(db.search('枝豆').first.food.ref, before.last.food.ref);
        db.usage.clear();
      }
    });

    test('kcalのみ公表のチェーンは PFC 不明のまま（捏造しない）', () {
      final hama = db.all.where((r) => r.chain == 'はま寿司').toList();
      expect(hama, isNotEmpty);
      expect(hama.every((r) => r.pfcUnknown), isTrue);
    });

    test('キッチンオリジンの量り売りは100gあたり', () {
      final ko = db.all.where((r) => r.chain == 'キッチンオリジン' && r.per100g).toList();
      expect(ko.length, greaterThanOrEqualTo(50));
    });

    test('写真判定の照合：主食は成分表（100gあたり）を優先、チェーンは対象外', () {
      final drafts = matchJudgement(
        db,
        const PhotoJudgement([
          JudgedDish(name: 'ごはん', category: DishCategory.rice, sizeClass: 2, confidence: 0.9),
          JudgedDish(name: '鶏の唐揚げ', candidates: ['からあげ'], category: DishCategory.main, confidence: 0.8),
          JudgedDish(name: '謎の料理ふがほげ', confidence: 0.9),
        ]),
      );
      expect(drafts[0].portion!.food.ref, 's:1088');
      final rice = computePortion(drafts[0].portion!);
      expect(rice.grams, 234); // 180g × 1.3
      expect(rice.kcal, 365); // 156 × 2.34
      expect(drafts[1].portion!.food.source, isNot(FoodSource.chain));
      expect(drafts[2].portion, isNull);
      expect(drafts[2].needsConfirm, isTrue);
    });
  });
}
