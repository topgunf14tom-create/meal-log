import '../../app_services.dart';
import '../../core/nutrition.dart';

/// その日の残り予算（kcal・脂質）。検索候補の「収まる／超える」表示に使う
class DayBudget {
  const DayBudget({required this.kcal, required this.fat});

  /// 残り kcal（目標＋上乗せの消費 − 摂取）
  final double kcal;

  /// 残り脂質 g（目標 − 摂取）
  final double fat;

  DayBudget minus(double k, double f) => DayBudget(kcal: kcal - k, fat: fat - f);

  static Future<DayBudget> load(String date) async {
    final s = AppServices.I;
    final goal = await s.db.goalOn(date);
    final meals = await s.db.mealsOn(date);
    final total = Pfc.sum(meals.expand((m) => m.items));
    var burn = 0.0;
    if (s.settings.healthEnabled && s.settings.addBurnToGoal) {
      burn = (await s.db.activityOn(date))?.totalKcal.roundToDouble() ?? 0;
    }
    final t = targetGrams(goal);
    return DayBudget(kcal: goal.targetKcal + burn - total.kcal, fat: t.f - total.f);
  }
}

enum BudgetFit { ok, fatOver, kcalOver }

BudgetFit budgetFit(DayBudget b, double kcal, double fat) {
  if (kcal > b.kcal) return BudgetFit.kcalOver;
  if (fat > b.fat) return BudgetFit.fatOver;
  return BudgetFit.ok;
}
