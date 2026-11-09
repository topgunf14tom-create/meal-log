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
      );
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
