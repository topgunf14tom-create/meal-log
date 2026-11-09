import '../app_services.dart';
import '../core/dates.dart';
import '../core/nutrition.dart';

/// ホーム画面のウィジェットに今日の値を送る（失敗しても無視）
Future<void> updateHomeWidget() async {
  final s = AppServices.I;
  try {
    final today = ymd(DateTime.now());
    final meals = await s.db.mealsOn(today);
    final goal = await s.db.goalOn(today);
    final intake = Pfc.sum(meals.expand((m) => m.items)).kcal;
    final activity = s.settings.healthEnabled ? await s.db.activityOn(today) : null;
    final double burn = activity?.totalKcal ?? 0.0;
    final target = goal.targetKcal + (s.settings.addBurnToGoal ? burn : 0);
    await s.device.updateWidget({
      'date': today,
      'intake': intake.round(),
      'target': target.round(),
      'steps': activity?.totalSteps ?? -1,
      'burn': activity == null ? -1 : burn.round(),
    });
  } catch (_) {}
}

/// 記録が変わったとき・アプリを開いたときにまとめて行う後処理
Future<void> afterDataChanged() async {
  await updateHomeWidget();
  try {
    await AppServices.I.reminders.reschedule();
  } catch (_) {}
}
