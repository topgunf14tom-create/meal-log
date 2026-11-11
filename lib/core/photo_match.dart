/// 写真判定（料理名・量感クラス）を食品DBに照合し、量の指定（Portion）にする。
library;

import 'food_db.dart';
import 'photo_judge.dart';
import 'portion.dart';
import 'search_text.dart';

/// 編集画面に渡す1品分の下書き
class PortionDraft {
  const PortionDraft({
    this.portion,
    required this.label,
    this.candidates = const [],
    this.needsConfirm = false,
    this.fromPhoto = false,
    this.modelGrams,
    this.modelSizeClass,
    this.learned = false,
  });

  /// 照合できた食品と量（DBに無ければ null。利用者が検索して選ぶ）
  final Portion? portion;

  /// 写真判定の料理名（照合前の名前）
  final String label;
  final List<String> candidates;

  /// 確からしさが低い・候補が部分一致だけ → 記録前に確認が必要
  final bool needsConfirm;
  final bool fromPhoto;

  /// モデルのグラム推定（補助情報。計算には使わない）
  final double? modelGrams;

  /// AIが判定した量感クラス（量のクセで初期値をずらす前）
  final int? modelSizeClass;

  /// 以前に自分が選び直した対応で照合した
  final bool learned;
}

/// 照合の順：完全一致 → 同義語 → 部分一致（候補提示）。量感クラスはモデルの判定を初期値にする
List<PortionDraft> matchJudgement(FoodDb db, PhotoJudgement j) {
  return [
    for (final d in j.dishes) _matchOne(db, d),
  ];
}

/// 主食は成分表の値（100gあたり）を優先し、§6.1 の基準量（ごはん180g など）で量を決める
const _staples = <String, String>{
  'げんまい': 's:1085',
  'ごはん': 's:1088',
  'ご飯': 's:1088',
  '白米': 's:1088',
  'らいす': 's:1088',
  'めし': 's:1088',
  'うどん': 's:1039',
  'そば': 's:1128',
  '蕎麦': 's:1128',
  'らーめん': 's:1048',
  '中華めん': 's:1048',
  'そうめん': 's:1044',
  'すぱげってぃ': 's:1064',
  'ぱすた': 's:1064',
  '食ぱん': 's:1026',
};

FoodHit? _staple(FoodDb db, JudgedDish d) {
  if (d.category != DishCategory.rice && d.category != DishCategory.noodle && d.category != DishCategory.bread) {
    return null;
  }
  final k = searchKey(d.name);
  // 「カレーライス」「天ぷらそば」のような料理は主食だけにしない
  for (final e in _staples.entries) {
    final key = searchKey(e.key);
    if (k == key || k == '白$key' || k == '$keyの麺' || k == '$key（麺）') {
      final f = db.byRef(e.value);
      if (f != null) return FoodHit(f, 0);
    }
  }
  return null;
}

/// よく出る料理名 → 成分表の食品（同義語辞書。§4.4）。生の食材は調理法の油・砂糖をコードで足す
const Map<String, List<String>> dishCanon = {
  's:11123': ['豚の生姜焼き', '生姜焼き', 'しょうが焼き', '豚肉の生姜焼き', 'ポークソテー'],
  's:18050': ['ハンバーグ', 'ハンバーグステーキ'],
  's:18002': ['餃子', '焼き餃子', 'ぎょうざ'],
  's:18012': ['しゅうまい', '焼売'],
  's:18049': ['麻婆豆腐', 'マーボー豆腐'],
  's:18047': ['酢豚'],
  's:18048': ['八宝菜', '中華丼の具'],
  's:18057': ['チャーハン', '炒飯', '焼き飯'],
  's:18036': ['肉じゃが'],
  's:18035': ['筑前煮', '煮しめ'],
  's:18033': ['きんぴらごぼう', 'きんぴら'],
  's:18028': ['豚汁', 'とん汁'],
  's:18018': ['コロッケ', 'ポテトコロッケ'],
  's:18020': ['エビフライ', 'えびフライ'],
  's:11276': ['とんかつ', 'ロースかつ'],
  's:10136': ['焼き鮭', '鮭の塩焼き', '塩鮭', '焼鮭'],
  's:10156': ['さばの塩焼き', '焼きさば', '鯖の塩焼き'],
  's:11222': ['チキンソテー', '鶏もも焼き'],
  's:18031': ['牛丼の具', '牛皿'],
  's:18030': ['親子丼の具'],
  's:18001': ['カレー', 'カレーソース', 'ビーフカレー', 'カレーのルー'],
  's:18041': ['ポークカレー'],
  's:6268': ['ほうれん草のおひたし', 'おひたし', 'ほうれん草'],
  's:6264': ['ブロッコリー', '茹でブロッコリー'],
  's:6061': ['キャベツ千切り', '千切りキャベツ', 'キャベツ'],
  's:6312': ['レタス'],
  's:6182': ['トマト', 'トマトスライス'],
  's:6065': ['きゅうり'],
  's:12019': ['だし巻き卵', 'だし巻き'],
  's:12018': ['卵焼き', '玉子焼き', '厚焼き卵'],
  's:18014': ['ピラフ', 'えびピラフ'],
  's:18039': ['もやしナムル', 'ナムル'],
  's:18037': ['ひじき煮', 'ひじきの煮物'],
  's:18032': ['切り干し大根', '切り干し大根の煮物'],
};

final Map<String, String> _canonIndex = {
  for (final e in dishCanon.entries)
    for (final n in e.value) searchKey(n): e.key,
};

FoodHit? _canon(FoodDb db, JudgedDish d) {
  for (final n in d.lookupNames) {
    final ref = _canonIndex[searchKey(n)];
    final f = db.byRef(ref);
    if (f != null) return FoodHit(f, 0);
  }
  return null;
}

FoodHit? _learnedHit(FoodDb db, JudgedDish d) {
  for (final n in d.lookupNames) {
    final f = db.byRef(db.learnedDish[searchKey(n)]);
    if (f != null) return FoodHit(f, 0);
  }
  return null;
}

PortionDraft _matchOne(FoodDb db, JudgedDish d) {
  final learned = _learnedHit(db, d);
  final hit = learned ?? _staple(db, d) ?? _canon(db, d) ?? db.bestMatch(d.lookupNames);
  if (hit == null) {
    return PortionDraft(
      label: d.name,
      candidates: d.candidates,
      needsConfirm: true,
      fromPhoto: true,
      modelGrams: d.grams,
      modelSizeClass: d.sizeClass,
    );
  }
  return PortionDraft(
    portion: Portion(
      food: hit.food,
      category: d.category,
      sizeClass: applyClassBias(d.sizeClass, db.classBias[hit.food.ref]),
      cook: d.cook,
    ),
    label: d.name,
    candidates: d.candidates,
    needsConfirm: d.needsConfirm || hit.tier >= 2,
    fromPhoto: true,
    modelGrams: d.grams,
    modelSizeClass: d.sizeClass,
    learned: learned != null,
  );
}
