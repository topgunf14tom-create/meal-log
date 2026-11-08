enum MealType { breakfast, lunch, dinner, snack }

extension MealTypeLabel on MealType {
  String get label {
    switch (this) {
      case MealType.breakfast:
        return '朝食';
      case MealType.lunch:
        return '昼食';
      case MealType.dinner:
        return '夕食';
      case MealType.snack:
        return '間食';
    }
  }
}

MealType mealTypeFromName(String name) =>
    MealType.values.firstWhere((t) => t.name == name, orElse: () => MealType.snack);

/// 時刻から食事区分を推定する
MealType guessMealType(DateTime t) {
  final m = t.hour * 60 + t.minute;
  if (m >= 4 * 60 && m < 10 * 60 + 30) return MealType.breakfast;
  if (m >= 10 * 60 + 30 && m < 15 * 60) return MealType.lunch;
  if (m >= 17 * 60 && m < 23 * 60) return MealType.dinner;
  return MealType.snack;
}
