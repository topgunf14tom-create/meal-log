import 'dart:convert';

import '../core/activity.dart';
import '../core/meal_type.dart';

double? toDoubleOrNull(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) {
    final cleaned = v.replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(cleaned);
  }
  return null;
}

double toDouble(Object? v, [double fallback = 0]) => toDoubleOrNull(v) ?? fallback;

const _confidences = {'high', 'medium', 'low'};
const _sourceTypes = {'official', 'reference', 'estimate', 'manual'};

/// 料理1品
class MealItem {
  const MealItem({
    this.id,
    this.name = '',
    this.amount = 1,
    this.unit = '人前',
    this.grams,
    this.kcal = 0,
    this.protein = 0,
    this.fat = 0,
    this.carbs = 0,
    this.confidence = 'medium',
    this.sourceType = 'estimate',
    this.sourceUrl,
    this.foodRef,
    this.sizeClass,
    this.ratio = 1,
    this.detail,
    this.pfcUnknown = false,
  });

  final int? id;
  final String name;
  final double amount;
  final String unit;
  final double? grams;
  final double kcal;
  final double protein;
  final double fat;
  final double carbs;

  /// high / medium / low
  final String confidence;

  /// official / reference / estimate / manual
  final String sourceType;
  final String? sourceUrl;

  /// 食品DBの参照（s:成分表ID / c:チェーン / i:居酒屋 / b:朝食 / u:登録食品）。値は記録時点で固定し、DB更新で再計算しない
  final String? foodRef;

  /// 量感クラス 0=少なめ 1=普通 2=多め 3=大盛（写真判定・成分表の食品）
  final int? sizeClass;

  /// 食べた割合（取り分け・残し。値はすでに掛けてある）
  final double ratio;

  /// 計算の内訳（調理油の加算・PFC補完など）
  final String? detail;

  /// kcal のみ分かり PFC が不明（P・F・C は 0 として記録）
  final bool pfcUnknown;

  static const manual = MealItem(name: '', confidence: 'high', sourceType: 'manual');

  /// 量を factor 倍した値（kcal・PFC・g を按分）
  MealItem scaled(double factor) => MealItem(
        id: id,
        name: name,
        amount: amount * factor,
        unit: unit,
        grams: grams == null ? null : grams! * factor,
        kcal: kcal * factor,
        protein: protein * factor,
        fat: fat * factor,
        carbs: carbs * factor,
        confidence: confidence,
        sourceType: sourceType,
        sourceUrl: sourceUrl,
        foodRef: foodRef,
        sizeClass: sizeClass,
        ratio: ratio,
        detail: detail,
        pfcUnknown: pfcUnknown,
      );

  /// 一部の項目だけ変えた複製
  MealItem copyWith({String? name, double? ratio, String? detail, String? sourceType, String? confidence}) => MealItem(
        id: id,
        name: name ?? this.name,
        amount: amount,
        unit: unit,
        grams: grams,
        kcal: kcal,
        protein: protein,
        fat: fat,
        carbs: carbs,
        confidence: confidence ?? this.confidence,
        sourceType: sourceType ?? this.sourceType,
        sourceUrl: sourceUrl,
        foodRef: foodRef,
        sizeClass: sizeClass,
        ratio: ratio ?? this.ratio,
        detail: detail ?? this.detail,
        pfcUnknown: pfcUnknown,
      );

  factory MealItem.fromJson(Map<String, dynamic> j) {
    final name = j['name']?.toString().trim() ?? '';
    final unit = j['unit']?.toString().trim() ?? '';
    final conf = j['confidence']?.toString().toLowerCase() ?? '';
    final src = j['source_type']?.toString().toLowerCase() ?? '';
    final url = j['source_url']?.toString().trim() ?? '';
    return MealItem(
      name: name.isEmpty ? '不明な料理' : name,
      amount: toDouble(j['amount'], 1),
      unit: unit.isEmpty ? '人前' : unit,
      grams: toDoubleOrNull(j['grams']),
      kcal: toDouble(j['kcal']),
      protein: toDouble(j['protein_g']),
      fat: toDouble(j['fat_g']),
      carbs: toDouble(j['carbs_g']),
      confidence: _confidences.contains(conf) ? conf : 'medium',
      sourceType: _sourceTypes.contains(src) ? src : 'estimate',
      sourceUrl: (url.isEmpty || url == 'null') ? null : url,
      foodRef: _str(j['food_ref']),
      sizeClass: (j['size_class'] as num?)?.toInt(),
      ratio: toDouble(j['ratio'], 1),
      detail: _str(j['detail']),
      pfcUnknown: j['pfc_unknown'] == true || j['pfc_unknown'] == 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'amount': amount,
        'unit': unit,
        'grams': grams,
        'kcal': kcal,
        'protein_g': protein,
        'fat_g': fat,
        'carbs_g': carbs,
        'confidence': confidence,
        'source_type': sourceType,
        'source_url': sourceUrl,
        if (foodRef != null) 'food_ref': foodRef,
        if (sizeClass != null) 'size_class': sizeClass,
        if (ratio != 1) 'ratio': ratio,
        if (detail != null) 'detail': detail,
        if (pfcUnknown) 'pfc_unknown': true,
      };

  Map<String, Object?> toDbMap(int mealId) => {
        'meal_id': mealId,
        'name': name,
        'amount': amount,
        'unit': unit,
        'grams': grams,
        'kcal': kcal,
        'protein_g': protein,
        'fat_g': fat,
        'carbs_g': carbs,
        'confidence': confidence,
        'source_type': sourceType,
        'source_url': sourceUrl,
        'food_ref': foodRef,
        'size_class': sizeClass,
        'ratio': ratio,
        'detail': detail,
        'pfc_unknown': pfcUnknown ? 1 : 0,
      };

  factory MealItem.fromDbMap(Map<String, Object?> m) => MealItem(
        id: m['id'] as int?,
        name: m['name'] as String? ?? '',
        amount: toDouble(m['amount'], 1),
        unit: m['unit'] as String? ?? '人前',
        grams: toDoubleOrNull(m['grams']),
        kcal: toDouble(m['kcal']),
        protein: toDouble(m['protein_g']),
        fat: toDouble(m['fat_g']),
        carbs: toDouble(m['carbs_g']),
        confidence: m['confidence'] as String? ?? 'medium',
        sourceType: m['source_type'] as String? ?? 'estimate',
        sourceUrl: m['source_url'] as String?,
        foodRef: m['food_ref'] as String?,
        sizeClass: (m['size_class'] as num?)?.toInt(),
        ratio: toDouble(m['ratio'], 1),
        detail: m['detail'] as String?,
        pfcUnknown: (m['pfc_unknown'] as num?)?.toInt() == 1,
      );
}

String? _str(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty || s == 'null') ? null : s;
}

/// 1回の食事（複数の料理を含む）
class Meal {
  const Meal({
    this.id,
    required this.date,
    required this.type,
    required this.createdAt,
    this.photoPath,
    this.modelUsed,
    this.note,
    this.items = const [],
  });

  final int? id;

  /// yyyy-MM-dd
  final String date;
  final MealType type;
  final DateTime createdAt;
  final String? photoPath;
  final String? modelUsed;
  final String? note;
  final List<MealItem> items;

  Map<String, Object?> toDbMap() => {
        'date': date,
        'meal_type': type.name,
        'created_at': createdAt.toIso8601String(),
        'photo_path': photoPath,
        'model_used': modelUsed,
        'note': note,
      };

  factory Meal.fromDbMap(Map<String, Object?> m, List<MealItem> items) => Meal(
        id: m['id'] as int?,
        date: m['date'] as String? ?? '',
        type: mealTypeFromName(m['meal_type'] as String? ?? ''),
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
        photoPath: m['photo_path'] as String?,
        modelUsed: m['model_used'] as String?,
        note: m['note'] as String?,
        items: items,
      );
}

/// 目標（start_date 以降に適用）
class Goal {
  const Goal({
    required this.startDate,
    required this.targetKcal,
    required this.pRatio,
    required this.fRatio,
    required this.cRatio,
  });

  final String startDate;
  final int targetKcal;
  final int pRatio;
  final int fRatio;
  final int cRatio;

  factory Goal.defaults(String date) =>
      Goal(startDate: date, targetKcal: 2000, pRatio: 20, fRatio: 25, cRatio: 55);

  Map<String, Object?> toDbMap() => {
        'start_date': startDate,
        'target_kcal': targetKcal,
        'p_ratio': pRatio,
        'f_ratio': fRatio,
        'c_ratio': cRatio,
      };

  factory Goal.fromDbMap(Map<String, Object?> m) => Goal(
        startDate: m['start_date'] as String? ?? '',
        targetKcal: (m['target_kcal'] as num?)?.toInt() ?? 2000,
        pRatio: (m['p_ratio'] as num?)?.toInt() ?? 20,
        fRatio: (m['f_ratio'] as num?)?.toInt() ?? 25,
        cRatio: (m['c_ratio'] as num?)?.toInt() ?? 55,
      );
}

class WeightEntry {
  const WeightEntry({required this.date, required this.kg, this.source = sourceManual, this.bodyFatPct});

  /// 手入力・InBody の QR（ヘルスコネクトの値では上書きしない）
  static const sourceManual = 'manual';

  /// ヘルスコネクトから自動取り込み
  static const sourceHealth = 'health';

  /// yyyy-MM-dd
  final String date;
  final double kg;
  final String source;
  final double? bodyFatPct;

  bool get isAuto => source == sourceHealth;

  factory WeightEntry.fromDbMap(Map<String, Object?> m) => WeightEntry(
        date: m['date'] as String? ?? '',
        kg: toDouble(m['weight_kg']),
        source: m['source'] as String? ?? sourceManual,
        bodyFatPct: m['body_fat_pct'] == null ? null : toDouble(m['body_fat_pct']),
      );
}

/// 1日の活動（ヘルスコネクトから計算した消費カロリー）
class ActivityDay {
  const ActivityDay({
    required this.date,
    required this.totalSteps,
    required this.walkSteps,
    required this.walkKcal,
    required this.exercises,
    required this.syncedAt,
  });

  /// yyyy-MM-dd
  final String date;
  final int totalSteps;
  final int walkSteps;
  final double walkKcal;
  final List<ExerciseEntry> exercises;
  final DateTime syncedAt;

  double get exerciseKcal => exercises.fold(0.0, (a, e) => a + e.kcal);
  double get totalKcal => walkKcal + exerciseKcal;

  Map<String, Object?> toDbMap() => {
        'date': date,
        'steps': totalSteps,
        'walk_steps': walkSteps,
        'walk_kcal': walkKcal,
        'exercise_kcal': exerciseKcal,
        'exercises_json': jsonEncode(exercises.map((e) => e.toJson()).toList()),
        'synced_at': syncedAt.toIso8601String(),
      };

  factory ActivityDay.fromDbMap(Map<String, Object?> m) {
    List<ExerciseEntry> ex = const [];
    try {
      final list = jsonDecode(m['exercises_json'] as String? ?? '[]') as List;
      ex = list.whereType<Map>().map((e) => ExerciseEntry.fromJson(e.cast<String, dynamic>())).toList();
    } catch (_) {}
    return ActivityDay(
      date: m['date'] as String? ?? '',
      totalSteps: (m['steps'] as num?)?.toInt() ?? 0,
      walkSteps: (m['walk_steps'] as num?)?.toInt() ?? 0,
      walkKcal: toDouble(m['walk_kcal']),
      exercises: ex,
      syncedAt: DateTime.tryParse(m['synced_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class UsageSummary {
  const UsageSummary({
    this.requests = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.webSearches = 0,
    this.usd = 0,
  });

  final int requests;
  final int inputTokens;
  final int outputTokens;
  final int webSearches;
  final double usd;
}

/// 保存した InBody の結果。詳細は [raw]（QR の文字列）を解析し直して表示する
class InBodyRecord {
  const InBodyRecord({
    this.id,
    required this.date,
    this.measuredAt,
    required this.raw,
    required this.weightKg,
    required this.smmKg,
    required this.bfmKg,
    required this.pbf,
    required this.score,
    required this.createdAt,
  });

  final int? id;

  /// 記録日 yyyy-MM-dd
  final String date;

  /// 用紙に印字された測定日時（InBody 本体の時計）
  final DateTime? measuredAt;
  final String raw;
  final double weightKg;
  final double smmKg;
  final double bfmKg;
  final double pbf;
  final int score;
  final DateTime createdAt;

  Map<String, Object?> toDbMap() => {
        'date': date,
        'measured_at': measuredAt?.toIso8601String(),
        'raw': raw,
        'weight_kg': weightKg,
        'smm_kg': smmKg,
        'bfm_kg': bfmKg,
        'pbf': pbf,
        'score': score,
        'created_at': createdAt.toIso8601String(),
      };

  factory InBodyRecord.fromDbMap(Map<String, Object?> m) => InBodyRecord(
        id: m['id'] as int?,
        date: m['date'] as String? ?? '',
        measuredAt: DateTime.tryParse(m['measured_at'] as String? ?? ''),
        raw: m['raw'] as String? ?? '',
        weightKg: toDouble(m['weight_kg']),
        smmKg: toDouble(m['smm_kg']),
        bfmKg: toDouble(m['bfm_kg']),
        pbf: toDouble(m['pbf']),
        score: (m['score'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}

/// よく食べるもの
class FrequentItem {
  const FrequentItem({required this.item, required this.count, required this.lastDate});

  final MealItem item;
  final int count;

  /// 最後に食べた日 yyyy-MM-dd
  final String lastDate;
}

/// 「いつもの」：ホームから1タップで記録し直せる食事（単品・組み合わせ）
class Favorite {
  const Favorite({this.id, required this.name, required this.items, this.useCount = 0, this.mealType});

  final int? id;
  final String name;
  final List<MealItem> items;
  final int useCount;

  /// 登録したときの食事区分（null なら時刻から推定）
  final String? mealType;

  double get kcal => items.fold(0.0, (a, i) => a + i.kcal);

  Map<String, Object?> toDbMap() => {
        'name': name,
        'items_json': jsonEncode(items.map((e) => e.toJson()).toList()),
        'use_count': useCount,
        'meal_type': mealType,
      };

  factory Favorite.fromDbMap(Map<String, Object?> m) {
    var items = <MealItem>[];
    try {
      final list = jsonDecode(m['items_json'] as String? ?? '[]') as List;
      items = list.whereType<Map>().map((e) => MealItem.fromJson(e.cast<String, dynamic>())).toList();
    } catch (_) {}
    return Favorite(
      id: m['id'] as int?,
      name: m['name'] as String? ?? '',
      items: items,
      useCount: (m['use_count'] as num?)?.toInt() ?? 0,
      mealType: m['meal_type'] as String?,
    );
  }
}

/// 個人DB（自分で登録した食品・栄養成分表示の読み取り結果・JAN）
class UserFood {
  const UserFood({
    this.id,
    required this.name,
    this.jan,
    required this.kcal,
    this.protein,
    this.fat,
    this.carbs,
    this.salt,
    this.unitLabel = '1食',
    this.grams,
    this.per100g = false,
    this.estimated = false,
  });

  final int? id;
  final String name;
  final String? jan;
  final double kcal;
  final double? protein;
  final double? fat;
  final double? carbs;
  final double? salt;
  final String unitLabel;
  final double? grams;
  final bool per100g;

  /// 推定値で登録したもの（町田商店の「いつもの注文」など）
  final bool estimated;

  Map<String, Object?> toDbMap() => {
        'name': name,
        'jan': jan,
        'kcal': kcal,
        'protein_g': protein,
        'fat_g': fat,
        'carbs_g': carbs,
        'salt_g': salt,
        'unit_label': unitLabel,
        'grams': grams,
        'per100g': per100g ? 1 : 0,
        'estimated': estimated ? 1 : 0,
      };

  factory UserFood.fromDbMap(Map<String, Object?> m) => UserFood(
        id: m['id'] as int?,
        name: m['name'] as String? ?? '',
        jan: m['jan'] as String?,
        kcal: toDouble(m['kcal']),
        protein: toDoubleOrNull(m['protein_g']),
        fat: toDoubleOrNull(m['fat_g']),
        carbs: toDoubleOrNull(m['carbs_g']),
        salt: toDoubleOrNull(m['salt_g']),
        unitLabel: m['unit_label'] as String? ?? '1食',
        grams: toDoubleOrNull(m['grams']),
        per100g: (m['per100g'] as num?)?.toInt() == 1,
        estimated: (m['estimated'] as num?)?.toInt() == 1,
      );
}
