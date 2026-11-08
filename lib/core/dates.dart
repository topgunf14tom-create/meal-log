String _two(int n) => n.toString().padLeft(2, '0');

/// yyyy-MM-dd
String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

/// yyyy-MM
String ym(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}';

DateTime parseYmd(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

/// 9/28(月)
String jpDate(DateTime d) => '${d.month}/${d.day}(${_weekdays[d.weekday - 1]})';

String shortDate(DateTime d) => '${d.month}/${d.day}';
