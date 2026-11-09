/// 1日分の収支の材料
class BalanceDay {
  const BalanceDay({required this.date, required this.intakeKcal, required this.activityKcal});

  final DateTime date;
  final double intakeKcal;

  /// 歩行＋運動（ヘルスコネクト）。無ければ 0
  final double activityKcal;
}

/// 体重の見込み
class WeightForecast {
  const WeightForecast({
    required this.days,
    required this.avgIntake,
    required this.avgBurn,
    required this.bmr,
    required this.bmrEstimated,
    required this.kgPer30Days,
    this.trendKgPer30Days,
  });

  /// 計算に使った日数（食事の記録がある日）
  final int days;
  final double avgIntake;

  /// 1日の消費（基礎代謝×1.1＋歩行・運動）
  final double avgBurn;
  final double bmr;
  final bool bmrEstimated;

  /// 摂取と消費の差から見た 30日後の体重変化（kg）
  final double kgPer30Days;

  /// 実際の体重の推移（直線の傾き）から見た 30日後の変化（kg）。記録が少なければ null
  final double? trendKgPer30Days;

  double get avgBalance => avgIntake - avgBurn;
}

/// 体脂肪 1kg ≒ 7200kcal
const kcalPerKg = 7200.0;

/// 体重 kg からの基礎代謝の目安（InBody の値が無いとき）
double estimateBmr(double weightKg) => weightKg * 22;

/// [days] のうち食事の記録がある日（摂取 > 0）で平均をとる。2日未満なら null
WeightForecast? forecastWeight({
  required List<BalanceDay> days,
  required double? bmrFromInBody,
  required double weightKg,
  List<(DateTime, double)> weights = const [],
}) {
  final rec = days.where((d) => d.intakeKcal > 0).toList();
  if (rec.length < 2) return null;
  final bmr = bmrFromInBody ?? estimateBmr(weightKg);
  final avgIntake = rec.fold<double>(0, (a, d) => a + d.intakeKcal) / rec.length;
  final avgActivity = rec.fold<double>(0, (a, d) => a + d.activityKcal) / rec.length;
  final avgBurn = bmr * 1.1 + avgActivity;
  return WeightForecast(
    days: rec.length,
    avgIntake: avgIntake,
    avgBurn: avgBurn,
    bmr: bmr,
    bmrEstimated: bmrFromInBody == null,
    kgPer30Days: (avgIntake - avgBurn) * 30 / kcalPerKg,
    trendKgPer30Days: weightTrendPer30Days(weights),
  );
}

/// 体重の直線回帰の傾き × 30日。3点未満、または期間が7日未満なら null
double? weightTrendPer30Days(List<(DateTime, double)> weights) {
  if (weights.length < 3) return null;
  final t0 = weights.first.$1;
  final xs = weights.map((w) => w.$1.difference(t0).inHours / 24).toList();
  if (xs.last - xs.first < 7) return null;
  final ys = weights.map((w) => w.$2).toList();
  final n = xs.length;
  final mx = xs.reduce((a, b) => a + b) / n;
  final my = ys.reduce((a, b) => a + b) / n;
  var sxy = 0.0, sxx = 0.0;
  for (var i = 0; i < n; i++) {
    sxy += (xs[i] - mx) * (ys[i] - my);
    sxx += (xs[i] - mx) * (xs[i] - mx);
  }
  if (sxx == 0) return null;
  return sxy / sxx * 30;
}
