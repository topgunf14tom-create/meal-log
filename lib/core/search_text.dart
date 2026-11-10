/// 食品検索用の文字列正規化と同義語（表記ゆれ）。端末内で完結し、通信・LLMは使わない。
library;

/// 検索キー：全角英数→半角、カタカナ→ひらがな、小文字化、空白と記号を除去
String searchKey(String s) {
  final b = StringBuffer();
  for (final rune in s.runes) {
    var c = rune;
    if (c >= 0xFF01 && c <= 0xFF5E) c -= 0xFEE0; // 全角ASCII → 半角
    if (c >= 0x30A1 && c <= 0x30F6) c -= 0x60; // カタカナ → ひらがな
    if (_dropChars.contains(c)) continue;
    final ch = String.fromCharCode(c);
    if (ch.trim().isEmpty) continue;
    b.write(ch);
  }
  return b.toString().toLowerCase();
}

/// 検索キーから除く記号
final Set<int> _dropChars = {
  for (final ch in '/／・･［］[]（）()＜＞<>「」『』【】、。,.!！?？～〜~-‐−—_　"\'“”：:;；+＋*＊#＃'.runes) ch,
};

/// 表記ゆれ・別名のグループ。同じグループの語は検索時に相互に置き換えて探す。
/// 例：「からあげ」で「唐揚げ」「から揚げ」にヒット、「生中」で「生ビール（中ジョッキ）」にヒット
const List<List<String>> synonymGroups = [
  ['ごはん', 'ご飯', '御飯', 'めし', '飯', 'ライス', '白米', '白ご飯'],
  ['みそしる', 'みそ汁', '味噌汁', 'おみおつけ'],
  ['みそ', '味噌'],
  ['からあげ', '唐揚げ', 'から揚げ', '唐揚', 'からあげ'],
  ['ぎょうざ', '餃子', 'ギョーザ', 'ギョウザ'],
  ['しゅうまい', '焼売', 'シューマイ'],
  ['たまご', '卵', '玉子', '鶏卵'],
  ['たまごやき', '卵焼き', '玉子焼き', 'だし巻き卵', 'だしまき'],
  ['やきとり', '焼き鳥', '焼鳥'],
  ['さけ', '鮭', 'しゃけ', 'シャケ', 'しろさけ'],
  ['さば', '鯖'],
  ['さんま', '秋刀魚'],
  ['まぐろ', '鮪', 'マグロ'],
  ['えび', '海老', 'エビ'],
  ['いか', '烏賊', 'イカ'],
  ['たこ', '蛸', 'タコ'],
  ['ぶた', '豚', 'ポーク'],
  ['ぎゅう', '牛', 'うし', 'ビーフ'],
  ['とり', '鶏', '鳥', 'チキン', 'にわとり', '若どり'],
  ['とうふ', '豆腐'],
  ['なっとう', '納豆'],
  ['やさい', '野菜'],
  ['てんぷら', '天ぷら', '天麩羅'],
  ['とんかつ', '豚カツ', 'トンカツ'],
  ['ぽてさら', 'ポテサラ', 'ポテトサラダ'],
  ['なまちゅう', '生中', '生ビール中', '生ビール（中ジョッキ）'],
  ['なまびーる', '生ビール'],
  ['はいぼーる', 'ハイボール'],
  ['ぎゅうにゅう', '牛乳', 'ミルク', '普通牛乳'],
  ['こーひー', 'コーヒー', '珈琲'],
  ['おちゃ', 'お茶', '緑茶', 'せん茶'],
  ['ぱん', 'パン'],
  ['しょくぱん', '食パン'],
  ['うどん', '饂飩'],
  ['そば', '蕎麦'],
  ['らーめん', 'ラーメン', '拉麺', '中華そば', '中華めん'],
  ['すぱげってぃ', 'スパゲッティ', 'スパゲティ', 'パスタ'],
  ['かれー', 'カレー', 'カレーライス'],
  ['さしみ', '刺身', 'お造り'],
  ['すし', '寿司', '鮨', 'すし'],
  ['えだまめ', '枝豆'],
  ['ひややっこ', '冷奴', '冷やっこ'],
  ['つけもの', '漬物', 'お新香'],
  ['おにぎり', 'おむすび', 'にぎりめし'],
  ['ちゃーはん', 'チャーハン', '炒飯', '焼き飯'],
  ['やきそば', '焼きそば', '焼そば'],
  ['はんばーぐ', 'ハンバーグ'],
  ['さらだ', 'サラダ'],
  ['きゃべつ', 'キャベツ'],
  ['とまと', 'トマト'],
  ['ばなな', 'バナナ'],
  ['よーぐると', 'ヨーグルト'],
  ['ういんなー', 'ウインナー', 'ウィンナー', 'ソーセージ'],
  ['べーこん', 'ベーコン'],
  ['ちーず', 'チーズ'],
  ['おかゆ', 'お粥', '粥'],
  ['のり', '海苔'],
  ['わかめ', '若布'],
  ['きのこ', '茸'],
  ['もやし', '萌やし'],
  ['すいとうめし', '水稲めし'],
];

/// 正規化した語 → 同じグループの正規化した語
final Map<String, Set<String>> _synonymIndex = () {
  final m = <String, Set<String>>{};
  for (final g in synonymGroups) {
    final keys = g.map(searchKey).where((k) => k.isNotEmpty).toSet();
    for (final k in keys) {
      (m[k] ??= <String>{}).addAll(keys);
    }
  }
  return m;
}();

/// 正規化済みのクエリ1語から、表記ゆれを置き換えた候補を作る（元の語を含む。最大 [limit] 件）
List<String> expandSynonyms(String key, {int limit = 12}) {
  final out = <String>[key];
  if (key.isEmpty) return out;
  // 語全体が同義語グループに含まれる場合
  final whole = _synonymIndex[key];
  if (whole != null) {
    for (final w in whole) {
      if (!out.contains(w)) out.add(w);
    }
  }
  // 語の一部が同義語の場合（「みそしるのぐ」→「味噌汁のぐ」など）。長い語を優先して置き換える
  final parts = _synonymIndex.keys.where((k) => k.length >= 2 && k != key && key.contains(k)).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final p in parts) {
    for (final alt in _synonymIndex[p]!) {
      if (alt == p) continue;
      final v = key.replaceFirst(p, alt);
      if (!out.contains(v)) out.add(v);
      if (out.length >= limit) return out;
    }
  }
  return out;
}
