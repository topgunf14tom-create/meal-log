/// 歩数・運動からの消費カロリー計算（端末内の計算のみ。ヘルスコネクトの値を入力に使う）
///
/// - 歩幅 ＝ 身長 × 0.45
/// - 距離(km) ＝ 歩数 × 歩幅 ÷ 1000
/// - 歩行の消費カロリー(kcal) ≒ 体重(kg) × 距離(km) × 0.5
/// - 運動（Strava 等のエクササイズ）の時間帯の歩数は歩行カロリーから除外し、運動側で数える
/// - 運動のカロリーはヘルスコネクトの活動カロリー（その時間帯）を使い、無ければ METs で推定
/// - 1日の活動カロリー合計は使わない（歩数カロリーと二重計上になるため）
library;

import 'dart:math' as math;

/// 体重が分からないときの仮の値
const double fallbackWeightKg = 60;

/// 身長が分からないときの仮の値
const double fallbackHeightCm = 170;

double strideMeters(double heightCm) => heightCm * 0.45 / 100;

double walkDistanceKm(int steps, double heightCm) => steps * strideMeters(heightCm) / 1000;

double walkKcal(int steps, {required double heightCm, required double weightKg}) =>
    weightKg * walkDistanceKm(steps, heightCm) * 0.5;

/// 運動の種類（Kotlin 側 MainActivity.exerciseKey と同じキー）
enum ExerciseKind {
  running('ランニング', 9.8),
  walking('ウォーキング', 3.5),
  hiking('ハイキング', 6.0),
  biking('サイクリング', 7.5),
  swimming('水泳', 7.0),
  strength('筋トレ', 5.0),
  hiit('HIIT', 8.0),
  yoga('ヨガ', 2.5),
  snow('スキー・スノボ', 5.3),
  other('運動', 4.0);

  const ExerciseKind(this.label, this.mets);

  final String label;

  /// 推定用の METs（活動カロリーが記録されていないときに使う）
  final double mets;

  static ExerciseKind fromKey(String? key) =>
      ExerciseKind.values.firstWhere((e) => e.name == key, orElse: () => ExerciseKind.other);
}

/// 安静時を除いた正味の消費カロリー（(METs − 1) × 体重 × 時間）
double estimateExerciseKcal(ExerciseKind kind, Duration d, double weightKg) =>
    math.max(0, kind.mets - 1) * weightKg * d.inSeconds / 3600;

/// ヘルスコネクトから読んだエクササイズ1件
class ExerciseSession {
  const ExerciseSession({
    required this.start,
    required this.end,
    required this.kind,
    this.title,
    required this.origin,
  });

  final DateTime start;
  final DateTime end;
  final ExerciseKind kind;
  final String? title;

  /// 記録したアプリのパッケージ名
  final String origin;

  Duration get duration => end.difference(start);

  ExerciseSession clip(DateTime from, DateTime to) => ExerciseSession(
        start: start.isBefore(from) ? from : start,
        end: end.isAfter(to) ? to : end,
        kind: kind,
        title: title,
        origin: origin,
      );
}

/// 重なり合う運動をまとめたもの（同じ運動を複数アプリが記録した場合の二重計上を防ぐ）
class ExerciseGroup {
  ExerciseGroup(this.sessions);

  final List<ExerciseSession> sessions;

  DateTime get start => sessions.map((s) => s.start).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime get end => sessions.map((s) => s.end).reduce((a, b) => a.isAfter(b) ? a : b);

  /// 一番長い記録を代表にする
  ExerciseSession get main => sessions.reduce((a, b) => b.duration > a.duration ? b : a);

  List<String> get origins => sessions.map((s) => s.origin).toSet().toList();
}

/// 開始順に並べ、時間が重なるものを1つのグループにまとめる。[from]〜[to] の外は切り捨てる
List<ExerciseGroup> groupSessions(List<ExerciseSession> sessions, DateTime from, DateTime to) {
  final clipped = sessions
      .map((s) => s.clip(from, to))
      .where((s) => s.end.isAfter(s.start))
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final groups = <ExerciseGroup>[];
  DateTime? groupEnd;
  for (final s in clipped) {
    if (groups.isNotEmpty && groupEnd != null && s.start.isBefore(groupEnd)) {
      groups.last.sessions.add(s);
      if (s.end.isAfter(groupEnd)) groupEnd = s.end;
    } else {
      groups.add(ExerciseGroup([s]));
      groupEnd = s.end;
    }
  }
  return groups;
}

/// 1日分の運動（保存・表示用）
class ExerciseEntry {
  const ExerciseEntry({
    required this.kind,
    this.title,
    required this.start,
    required this.end,
    required this.kcal,
    required this.estimated,
    required this.origins,
  });

  final ExerciseKind kind;
  final String? title;
  final DateTime start;
  final DateTime end;
  final double kcal;

  /// true: METs による推定、false: ヘルスコネクトの活動カロリー
  final bool estimated;
  final List<String> origins;

  Duration get duration => end.difference(start);

  String get displayName => (title != null && title!.trim().isNotEmpty) ? title!.trim() : kind.label;

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'title': title,
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
        'kcal': kcal,
        'estimated': estimated,
        'origins': origins,
      };

  factory ExerciseEntry.fromJson(Map<String, dynamic> j) => ExerciseEntry(
        kind: ExerciseKind.fromKey(j['kind'] as String?),
        title: j['title'] as String?,
        start: DateTime.fromMillisecondsSinceEpoch((j['start'] as num?)?.toInt() ?? 0),
        end: DateTime.fromMillisecondsSinceEpoch((j['end'] as num?)?.toInt() ?? 0),
        kcal: (j['kcal'] as num?)?.toDouble() ?? 0,
        estimated: j['estimated'] == true,
        origins: ((j['origins'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );
}

/// ヘルスコネクトの区間集計（歩数・活動カロリー）。権限が無い項目は null
class RangeTotals {
  const RangeTotals({this.steps, this.kcal});

  final int? steps;
  final double? kcal;
}

/// 1日の消費カロリーの計算結果
class DayBurn {
  const DayBurn({
    required this.totalSteps,
    required this.walkSteps,
    required this.walkKcal,
    required this.exercises,
  });

  /// その日の歩数（ヘルスコネクトの重複除去済み合計）
  final int totalSteps;

  /// 運動中を除いた歩数
  final int walkSteps;
  final double walkKcal;
  final List<ExerciseEntry> exercises;

  double get exerciseKcal => exercises.fold(0.0, (a, e) => a + e.kcal);
  double get totalKcal => walkKcal + exerciseKcal;
}

/// [day] は1日全体の集計、[perGroup] は [groups] と同じ順の各運動時間帯の集計
DayBurn computeDayBurn({
  required RangeTotals day,
  required List<ExerciseGroup> groups,
  required List<RangeTotals> perGroup,
  required double heightCm,
  required double weightKg,
}) {
  assert(groups.length == perGroup.length);
  final total = day.steps ?? 0;
  var inExercise = 0;
  final exercises = <ExerciseEntry>[];
  for (var i = 0; i < groups.length; i++) {
    final g = groups[i];
    final t = perGroup[i];
    inExercise += t.steps ?? 0;
    final main = g.main;
    final measured = t.kcal;
    final useMeasured = measured != null && measured > 0;
    exercises.add(ExerciseEntry(
      kind: main.kind,
      title: main.title,
      start: g.start,
      end: g.end,
      kcal: useMeasured ? measured : estimateExerciseKcal(main.kind, g.end.difference(g.start), weightKg),
      estimated: !useMeasured,
      origins: g.origins,
    ));
  }
  final walkSteps = math.max(0, total - inExercise);
  return DayBurn(
    totalSteps: total,
    walkSteps: walkSteps,
    walkKcal: walkKcal(walkSteps, heightCm: heightCm, weightKg: weightKg),
    exercises: exercises,
  );
}

/// よく使うアプリのパッケージ名を表示名に
String originLabel(String pkg) {
  const known = {
    'com.strava': 'Strava',
    'com.inbody2014.inbody': 'InBody',
    'com.inbody.inbody2014': 'InBody',
    'com.google.android.apps.fitness': 'Fit',
    'com.google.android.apps.healthdata': 'ヘルスコネクト',
    'com.sec.android.app.shealth': 'Samsung Health',
    'com.fitbit.FitbitMobile': 'Fitbit',
    'com.garmin.android.apps.connectmobile': 'Garmin',
  };
  if (known.containsKey(pkg)) return known[pkg]!;
  if (pkg.toLowerCase().contains('inbody')) return 'InBody';
  if (pkg.toLowerCase().contains('strava')) return 'Strava';
  return pkg;
}
