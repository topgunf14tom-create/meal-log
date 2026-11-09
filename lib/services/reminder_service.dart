import '../core/dates.dart';
import '../core/meal_type.dart';
import '../core/reminders.dart';
import '../data/app_db.dart';
import '../data/app_settings.dart';
import 'device_service.dart';

/// 記録忘れの通知。アプリを開いたとき・記録したときに7日分を予約し直す
class ReminderService {
  ReminderService({required this.db, required this.settings, required this.device});

  final AppDb db;
  final AppSettings settings;
  final DeviceService device;

  bool get enabled => settings.raw('reminder_enabled') == 'true';

  /// 食事ごとの時刻（分）。'off' にした食事は含めない
  Map<MealType, int> get minutes {
    final out = <MealType, int>{};
    for (final t in reminderTypes) {
      final v = settings.raw('reminder_${t.name}');
      if (v == 'off') continue;
      out[t] = parseHm(v) ?? defaultReminderMinutes[t]!;
    }
    return out;
  }

  Future<void> setTime(MealType t, int? minutes) =>
      settings.set('reminder_${t.name}', minutes == null ? 'off' : formatHm(minutes));

  /// オンにする（通知の許可が出なければ false）
  Future<bool> enable() async {
    final ok = await device.requestNotifications();
    if (!ok) return false;
    await settings.set('reminder_enabled', 'true');
    await reschedule();
    return true;
  }

  Future<void> disable() async {
    await settings.set('reminder_enabled', 'false');
    await device.scheduleReminders(const []);
  }

  Future<void> reschedule() async {
    if (!enabled) return;
    final now = DateTime.now();
    final recorded = await db.mealTypesOn(ymd(now));
    final plans = planReminders(now: now, minutes: minutes, recordedToday: recorded);
    await device.scheduleReminders(plans.map((p) => p.toChannel()).toList());
  }
}
