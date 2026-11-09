import '../app_services.dart';
import '../core/dates.dart';
import '../core/forecast.dart';
import '../core/inbody.dart';

/// [from]〜[to] の記録から体重の見込みを計算する
Future<WeightForecast?> loadForecast(DateTime from, DateTime to) async {
  final s = AppServices.I;
  final f = ymd(from), t = ymd(to);
  final totals = await s.db.dailyTotals(f, t);
  final acts = {for (final a in await s.db.activitiesBetween(f, t)) a.date: a};
  final days = <BalanceDay>[];
  for (var d = dayOnly(from); !d.isAfter(dayOnly(to)); d = addDays(d, 1)) {
    final key = ymd(d);
    days.add(BalanceDay(
      date: d,
      intakeKcal: totals[key]?.kcal ?? 0.0,
      activityKcal: s.settings.healthEnabled ? (acts[key]?.totalKcal ?? 0.0) : 0.0,
    ));
  }
  double? bmr;
  final records = await s.db.inbodyResults();
  for (final r in records) {
    try {
      bmr = parseInBodyQr(r.raw).bmr.toDouble();
      break;
    } on InBodyFormatException {
      continue;
    }
  }
  final w = await s.db.weightOnOrBefore(t);
  final weights = (await s.db.weightsSince(ymd(addDays(dayOnly(to), -30))))
      .where((e) => e.date.compareTo(t) <= 0)
      .map((e) => (parseYmd(e.date), e.kg))
      .toList();
  return forecastWeight(days: days, bmrFromInBody: bmr, weightKg: w?.kg ?? 60, weights: weights);
}
