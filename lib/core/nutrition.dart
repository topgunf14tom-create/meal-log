import '../data/entities.dart';

/// kcal と PFC（g）の組
class Pfc {
  const Pfc(this.kcal, this.p, this.f, this.c);

  final double kcal;
  final double p;
  final double f;
  final double c;

  static const zero = Pfc(0, 0, 0, 0);

  Pfc operator +(Pfc o) => Pfc(kcal + o.kcal, p + o.p, f + o.f, c + o.c);

  static Pfc sum(Iterable<MealItem> items) =>
      items.fold(zero, (acc, i) => acc + Pfc(i.kcal, i.protein, i.fat, i.carbs));

  /// エネルギー比率（%）。P・Cは4kcal/g、Fは9kcal/g で計算
  ({double p, double f, double c}) energyRatio() {
    final ep = p * 4;
    final ef = f * 9;
    final ec = c * 4;
    final total = ep + ef + ec;
    if (total <= 0) return (p: 0, f: 0, c: 0);
    return (p: ep / total * 100, f: ef / total * 100, c: ec / total * 100);
  }
}

/// 目標から PFC の目標グラムを計算
Pfc targetGrams(Goal g) {
  final k = g.targetKcal.toDouble();
  return Pfc(k, k * g.pRatio / 100 / 4, k * g.fRatio / 100 / 9, k * g.cRatio / 100 / 4);
}
