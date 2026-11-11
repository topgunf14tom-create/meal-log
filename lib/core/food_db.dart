/// アプリ同梱の食品データベース（成分表・チェーン店公式値・居酒屋/朝食の定番辞書）と個人DBの検索。
/// 栄養値の唯一の出どころ。検索・照合は端末内で完結する（通信・LLM不要）。
library;

import 'dart:convert';

import 'search_text.dart';

enum FoodSource { personal, chain, izakaya, breakfast, seibun }

extension FoodSourceLabel on FoodSource {
  String get label => switch (this) {
        FoodSource.personal => '登録食品',
        FoodSource.chain => 'チェーン公式',
        FoodSource.izakaya => '居酒屋の定番',
        FoodSource.breakfast => '朝食の定番',
        FoodSource.seibun => '食品成分表',
      };

  /// 同じ一致度のときの並び（小さいほど上）。一般名の検索では定番辞書を先に、店名つきの検索はチェーンだけが残る
  int get priority => switch (this) {
        FoodSource.personal => 0,
        FoodSource.izakaya => 1,
        FoodSource.breakfast => 2,
        FoodSource.chain => 3,
        FoodSource.seibun => 4,
      };
}

/// 食品1件。値は [per100g] なら100gあたり、そうでなければ1食（1皿・1杯・1個）あたり
class FoodRecord {
  FoodRecord({
    required this.ref,
    required this.source,
    required this.name,
    this.chain,
    this.variant,
    this.group,
    required this.kcal,
    this.protein,
    this.fat,
    this.carbs,
    this.salt,
    this.fiber,
    this.per100g = false,
    this.servingGrams,
    this.servingLabel,
    this.estimated = false,
    this.aliases = const [],
    this.jan,
    this.sourceUrl,
  }) {
    nameKey = searchKey(name);
    aliasKeys = aliases.map(searchKey).where((k) => k.isNotEmpty).toList();
    fullKey = searchKey([chain ?? '', name, variant ?? '', ...aliases].join(' '));
  }

  /// 記録に残す参照キー（例 s:1088 / c:すき家:牛丼:並盛 / u:12）
  final String ref;
  final FoodSource source;

  /// 表示名（成分表は分類の区切りを空白にしたもの）
  final String name;
  final String? chain;
  final String? variant;

  /// 成分表の食品群・辞書のカテゴリ
  final String? group;
  final double? kcal;
  final double? protein;
  final double? fat;
  final double? carbs;
  final double? salt;
  final double? fiber;
  final bool per100g;

  /// 1食あたりの重さ（辞書・個人DB。分かるときだけ）
  final double? servingGrams;

  /// 1食の目安（例「1皿（120g）」）
  final String? servingLabel;

  /// 推定値（辞書の換算値など。公式値ではない）
  final bool estimated;
  final List<String> aliases;
  final String? jan;
  final String? sourceUrl;

  late final String nameKey;
  late final List<String> aliasKeys;
  late final String fullKey;

  /// kcal のみ公表で PFC が無い
  bool get pfcUnknown => protein == null || fat == null || carbs == null;

  /// 表示用の名前（チェーン名・サイズ込み）
  String get displayName {
    final v = (variant == null || variant!.isEmpty || per100g) ? '' : ' ${variant!}';
    return '$name$v';
  }

  String get subtitle {
    final parts = <String>[
      if (chain != null) chain! else source.label,
      if (per100g) '100gあたり' else if (servingLabel != null && servingLabel!.isNotEmpty) servingLabel!,
      if (estimated) '推定',
    ];
    return parts.join('・');
  }

  /// 成分表の値は調理済み（揚げ・炒め等）か（調理法デフォルトの油を足さない）
  bool get alreadyCooked {
    if (source != FoodSource.seibun) return true;
    return group == '調理済み流通食品類' ||
        RegExp(r'揚げ|フライ|天ぷら|いため|ソテー|焼き|ゆで|煮|めし|おにぎり').hasMatch(name);
  }
}

/// 検索結果1件
class FoodHit {
  const FoodHit(this.food, this.tier);

  final FoodRecord food;

  /// 0=完全一致 1=前方一致 2=部分一致
  final int tier;
}

/// 食品DB本体（メモリ上の索引）
class FoodDb {
  FoodDb({List<FoodRecord> records = const [], this.meta = const {}}) {
    for (final r in records) {
      add(r);
    }
  }

  final List<FoodRecord> _all = [];
  final Map<String, FoodRecord> _byRef = {};

  /// DBごとの出典・作成日（設定画面の表示用）
  final Map<String, String> meta;

  /// 利用回数（food_usage）。候補の並びに使う
  final Map<String, int> usage = {};

  /// 写真の料理名（正規化）→ 自分が選んだ食品（選び直した対応を覚える）
  final Map<String, String> learnedDish = {};

  /// 食品ごとの量のクセ（AI判定との差の平均）
  final Map<String, double> classBias = {};

  List<FoodRecord> get all => List.unmodifiable(_all);
  int get length => _all.length;

  int countOf(FoodSource s) => _all.where((r) => r.source == s).length;

  void add(FoodRecord r) {
    final old = _byRef[r.ref];
    if (old != null) _all.remove(old);
    _all.add(r);
    _byRef[r.ref] = r;
  }

  void removeRef(String ref) {
    final old = _byRef.remove(ref);
    if (old != null) _all.remove(old);
  }

  FoodRecord? byRef(String? ref) => ref == null ? null : _byRef[ref];

  FoodRecord? byJan(String jan) {
    for (final r in _all) {
      if (r.jan == jan) return r;
    }
    return null;
  }

  /// 横断検索：完全一致 → 前方一致 → 部分一致。同じ段の中では利用履歴の多い順、次に情報源の順。
  /// 空白で区切った複数語はすべてを含むもの（例「すき家 牛丼」）。
  List<FoodHit> search(String query, {int limit = 60, Set<FoodSource>? sources}) {
    final tokens = query.split(RegExp(r'[\s　]+')).map(searchKey).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return const [];
    final alts = [for (final t in tokens) expandSynonyms(t)];
    final hits = <FoodHit>[];
    for (final r in _all) {
      if (sources != null && !sources.contains(r.source)) continue;
      final tier = _tier(r, alts);
      if (tier != null) hits.add(FoodHit(r, tier));
    }
    hits.sort((a, b) {
      final t = a.tier.compareTo(b.tier);
      if (t != 0) return t;
      final u = (usage[b.food.ref] ?? 0).compareTo(usage[a.food.ref] ?? 0);
      if (u != 0) return u;
      final p = a.food.source.priority.compareTo(b.food.source.priority);
      if (p != 0) return p;
      return a.food.name.length.compareTo(b.food.name.length);
    });
    return hits.length > limit ? hits.sublist(0, limit) : hits;
  }

  /// 料理名に一番合う食品（写真判定の照合用）。候補名を順に「完全一致 → 同義語 → 部分一致」で探す。
  /// チェーン店の商品は写真判定の対象外なので除く。見つからなければ null
  FoodHit? bestMatch(List<String> names) {
    const photoSources = {FoodSource.personal, FoodSource.izakaya, FoodSource.breakfast, FoodSource.seibun};
    FoodHit? best;
    for (final n in names) {
      final hits = search(n, limit: 1, sources: photoSources);
      if (hits.isEmpty) continue;
      if (best == null || hits.first.tier < best.tier) best = hits.first;
      if (best.tier == 0) break;
    }
    if (best != null) return best;
    // 見つからなければ語尾を削って探す（「キャベツ千切り」→「キャベツ」）。部分一致扱いで要確認にする
    for (final n in names) {
      final k = searchKey(n);
      for (var len = k.length - 1; len >= 2; len--) {
        final hits = search(k.substring(0, len), limit: 1, sources: photoSources);
        if (hits.isNotEmpty) return FoodHit(hits.first.food, 2);
      }
    }
    return null;
  }

  static int? _tier(FoodRecord r, List<List<String>> alts) {
    if (alts.length == 1) {
      int? best;
      for (final a in alts.first) {
        int? t;
        if (r.nameKey == a || r.aliasKeys.contains(a)) {
          t = 0;
        } else if (r.nameKey.startsWith(a) || r.aliasKeys.any((k) => k.startsWith(a))) {
          t = 1;
        } else if (r.fullKey.contains(a)) {
          t = 2;
        }
        if (t != null && (best == null || t < best)) best = t;
        if (best == 0) break;
      }
      return best;
    }
    // 複数語：すべての語（いずれかの表記）を含むこと。最後の語が名前の先頭なら前方一致扱い
    for (final group in alts) {
      if (!group.any(r.fullKey.contains)) return null;
    }
    final last = alts.last;
    return last.any((a) => r.nameKey.startsWith(a)) ? 1 : 2;
  }
}

// ---------- JSON（同梱ファイル）からの読み込み ----------

double? _d(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

final _per100Variant = RegExp(r'^\s*100\s*(g|ｇ|ml|ｍｌ)\s*(あたり|当たり)?\s*$', caseSensitive: false);

/// 成分表の名前「穀類/こめ/［水稲めし］/精白米/うるち米」→「こめ ［水稲めし］ 精白米 うるち米」
String seibunDisplayName(String path) {
  final parts = path.split('/');
  final rest = parts.length > 1 ? parts.sublist(1) : parts;
  return rest.join(' ');
}

List<FoodRecord> parseSeibun(Map<String, dynamic> json) => [
      for (final e in (json['items'] as List? ?? const []).whereType<Map>())
        FoodRecord(
          ref: 's:${e['id']}',
          source: FoodSource.seibun,
          name: seibunDisplayName(e['name'].toString()),
          group: e['group']?.toString(),
          kcal: _d(e['kcal']),
          protein: _d(e['protein']),
          fat: _d(e['fat']),
          carbs: _d(e['carbs']),
          salt: _d(e['salt']),
          fiber: _d(e['fiber']),
          per100g: true,
          servingLabel: '100g',
        ),
    ];

List<FoodRecord> parseChains(Map<String, dynamic> json) {
  final out = <FoodRecord>[];
  for (final ch in (json['chains'] as List? ?? const []).whereType<Map>()) {
    final chain = ch['chain'].toString();
    final url = ch['source_url']?.toString();
    final seen = <String>{};
    for (final e in (ch['items'] as List? ?? const []).whereType<Map>()) {
      final name = e['name']?.toString().trim() ?? '';
      if (name.isEmpty || _d(e['kcal']) == null) continue;
      final variant = e['variant']?.toString().trim();
      var ref = 'c:$chain:$name:${variant ?? ''}';
      // 同名・同サイズが複数ある場合は番号を付ける
      var n = 2;
      while (!seen.add(ref)) {
        ref = 'c:$chain:$name:${variant ?? ''}#${n++}';
      }
      out.add(FoodRecord(
        ref: ref,
        source: FoodSource.chain,
        name: name,
        chain: chain,
        variant: (variant == null || variant.isEmpty) ? null : variant,
        group: chain,
        kcal: _d(e['kcal']),
        protein: _d(e['protein']),
        fat: _d(e['fat']),
        carbs: _d(e['carbs']),
        salt: _d(e['salt']),
        per100g: variant != null && _per100Variant.hasMatch(variant),
        sourceUrl: url,
      ));
    }
  }
  return out;
}

/// 居酒屋・朝食の定番辞書（1皿・1杯あたりの換算推定値）
List<FoodRecord> parseDictionary(Map<String, dynamic> json, FoodSource source) {
  final prefix = source == FoodSource.izakaya ? 'i' : 'b';
  return [
    for (final e in (json['items'] as List? ?? const []).whereType<Map>())
      FoodRecord(
        ref: '$prefix:${e['name']}',
        source: source,
        name: e['name'].toString(),
        group: e['category']?.toString(),
        kcal: _d(e['kcal']),
        protein: _d(e['protein']),
        fat: _d(e['fat']),
        carbs: _d(e['carbs']),
        salt: _d(e['salt']),
        fiber: _d(e['fiber']),
        servingGrams: _d(e['grams']),
        servingLabel: e['serving']?.toString(),
        estimated: e['estimated'] != false,
        aliases: [for (final a in (e['aliases'] as List? ?? const [])) a.toString()],
      ),
  ];
}

/// 同梱の4ファイル（JSON 文字列）から DB を作る。重いので別 isolate で呼ぶ
FoodDb buildFoodDb({
  required String seibunJson,
  required String chainsJson,
  required String izakayaJson,
  required String breakfastJson,
}) {
  final seibun = jsonDecode(seibunJson) as Map<String, dynamic>;
  final chains = jsonDecode(chainsJson) as Map<String, dynamic>;
  final izakaya = jsonDecode(izakayaJson) as Map<String, dynamic>;
  final breakfast = jsonDecode(breakfastJson) as Map<String, dynamic>;
  return FoodDb(
    records: [
      ...parseChains(chains),
      ...parseDictionary(izakaya, FoodSource.izakaya),
      ...parseDictionary(breakfast, FoodSource.breakfast),
      ...parseSeibun(seibun),
    ],
    meta: {
      'seibun_source': '${seibun['source'] ?? '日本食品標準成分表（八訂）増補2023年'}',
      'seibun_generated_at': '${seibun['generated_at'] ?? ''}',
      'chains_generated_at': '${chains['generated_at'] ?? ''}',
      'chains_count': '${(chains['chains'] as List? ?? const []).length}',
      'izakaya_updated': '${izakaya['updated'] ?? ''}',
      'breakfast_updated': '${breakfast['updated'] ?? ''}',
    },
  );
}
