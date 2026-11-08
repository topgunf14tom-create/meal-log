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
  const WeightEntry({required this.date, required this.kg});

  /// yyyy-MM-dd
  final String date;
  final double kg;

  factory WeightEntry.fromDbMap(Map<String, Object?> m) =>
      WeightEntry(date: m['date'] as String? ?? '', kg: toDouble(m['weight_kg']));
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
