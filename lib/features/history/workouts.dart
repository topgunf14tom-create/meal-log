import '../../app_services.dart';
import '../../core/activity.dart';
import '../../core/dates.dart';
import '../../core/strava_archive.dart';

/// 運動1回（Strava の取り込み、またはヘルスコネクトの記録）
class Workout {
  Workout({
    required this.kind,
    required this.title,
    required this.start,
    required this.elapsedS,
    this.movingS,
    this.distanceM,
    required this.kcal,
    required this.kcalEstimated,
    this.elevGainM,
    this.avgHr,
    this.stravaId,
    required this.sources,
  });

  final ExerciseKind kind;
  final String title;
  final DateTime start;
  final double elapsedS;
  final double? movingS;
  final double? distanceM;
  final double kcal;
  final bool kcalEstimated;
  final double? elevGainM;
  final double? avgHr;

  /// Strava から取り込んだものなら ID（詳細画面を開ける）
  final String? stravaId;
  final List<String> sources;

  DateTime get end => start.add(Duration(milliseconds: (elapsedS * 1000).round()));
  double get timeS => movingS ?? elapsedS;

  factory Workout.fromStrava(StravaActivity a, double weightKg) {
    final est = a.kcal == null;
    return Workout(
      kind: a.kind,
      title: a.name.isNotEmpty ? a.name : a.kind.label,
      start: a.start,
      elapsedS: a.elapsedS,
      movingS: a.movingS,
      distanceM: a.distanceM > 0 ? a.distanceM : null,
      kcal: a.kcal ?? estimateExerciseKcal(a.kind, Duration(seconds: a.movingS.round()), weightKg),
      kcalEstimated: est,
      elevGainM: a.elevGainM,
      avgHr: a.avgHr,
      stravaId: a.id,
      sources: const ['Strava（取り込み）'],
    );
  }

  factory Workout.fromHealth(ExerciseGroup g, double weightKg) {
    double? maxOf(Iterable<double?> v) {
      final l = v.whereType<double>().toList();
      return l.isEmpty ? null : l.reduce((a, b) => a > b ? a : b);
    }

    final d = g.end.difference(g.start);
    final kcal = maxOf(g.sessions.map((s) => s.kcal));
    return Workout(
      kind: g.main.kind,
      title: g.main.title?.isNotEmpty == true ? g.main.title! : g.main.kind.label,
      start: g.start,
      elapsedS: d.inSeconds.toDouble(),
      distanceM: maxOf(g.sessions.map((s) => s.distanceM)),
      kcal: kcal ?? estimateExerciseKcal(g.main.kind, d, weightKg),
      kcalEstimated: kcal == null,
      sources: g.origins.map(originLabel).toList(),
    );
  }
}

class WorkoutLoad {
  const WorkoutLoad({required this.workouts, required this.granted, this.error, required this.stravaCount});

  /// 新しい順
  final List<Workout> workouts;
  final Set<String> granted;
  final String? error;
  final int stravaCount;
}

bool _overlaps(Workout a, Workout b) {
  final s = a.start.isAfter(b.start) ? a.start : b.start;
  final e = a.end.isBefore(b.end) ? a.end : b.end;
  final overlap = e.difference(s).inSeconds;
  final shorter = a.elapsedS < b.elapsedS ? a.elapsedS : b.elapsedS;
  return overlap > 0 && overlap >= shorter * 0.5;
}

/// [from] 以降の運動。Strava の取り込みとヘルスコネクトで時間が重なるものは取り込み側を残す
Future<WorkoutLoad> loadWorkouts(DateTime from) async {
  final s = AppServices.I;
  final now = DateTime.now();
  final w = await s.db.weightOnOrBefore(ymd(now));
  final weight = w?.kg ?? 60;
  final stravas = (await s.db.stravaActivities(from: from)).map((a) => Workout.fromStrava(a, weight)).toList();
  final count = await s.db.stravaCount();

  var granted = <String>{};
  String? error;
  final health = <Workout>[];
  if (s.settings.healthEnabled) {
    try {
      granted = await s.health.granted();
      if (granted.contains('exercise')) {
        final sessions = await s.health.readSessions(from, now, metrics: true);
        for (final g in groupSessions(sessions, from, now)) {
          final hw = Workout.fromHealth(g, weight);
          if (!stravas.any((x) => _overlaps(x, hw))) health.add(hw);
        }
      }
    } catch (e) {
      error = '$e';
    }
  }
  final all = [...stravas, ...health]..sort((a, b) => b.start.compareTo(a.start));
  return WorkoutLoad(workouts: all, granted: granted, error: error, stravaCount: count);
}
