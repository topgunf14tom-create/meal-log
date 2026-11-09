import 'meal_type.dart';

/// 記録忘れの通知1件
class ReminderPlan {
  const ReminderPlan({required this.id, required this.at, required this.type});

  final int id;
  final DateTime at;
  final MealType type;

  String get title => '${type.label}の記録がまだです';
  String get body => 'タップして記録しましょう';

  Map<String, Object?> toChannel() => {'id': id, 'at': at.millisecondsSinceEpoch, 'title': title, 'body': body};
}

/// 通知する食事（間食は通知しない）
const reminderTypes = [MealType.breakfast, MealType.lunch, MealType.dinner];

/// 既定の通知時刻（分）
const defaultReminderMinutes = {
  MealType.breakfast: 9 * 60 + 30,
  MealType.lunch: 13 * 60 + 30,
  MealType.dinner: 20 * 60 + 30,
};

/// "9:30" → 570。読めなければ null
int? parseHm(String? s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s?.trim() ?? '');
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final mi = int.parse(m.group(2)!);
  if (h > 23 || mi > 59) return null;
  return h * 60 + mi;
}

String formatHm(int minutes) => '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';

/// [now] から [days] 日分の通知を作る。今日すでに記録した食事（[recordedToday]）と過ぎた時刻は除く
List<ReminderPlan> planReminders({
  required DateTime now,
  required Map<MealType, int> minutes,
  required Set<MealType> recordedToday,
  int days = 7,
}) {
  final out = <ReminderPlan>[];
  final today = DateTime(now.year, now.month, now.day);
  for (var d = 0; d < days; d++) {
    final day = DateTime(today.year, today.month, today.day + d);
    for (var i = 0; i < reminderTypes.length; i++) {
      final t = reminderTypes[i];
      final m = minutes[t];
      if (m == null) continue;
      if (d == 0 && recordedToday.contains(t)) continue;
      final at = DateTime(day.year, day.month, day.day, m ~/ 60, m % 60);
      if (!at.isAfter(now)) continue;
      out.add(ReminderPlan(id: d * reminderTypes.length + i, at: at, type: t));
    }
  }
  return out;
}
