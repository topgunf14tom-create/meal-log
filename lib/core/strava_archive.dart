import 'dart:convert';

import 'activity.dart';
import 'activity_files.dart';
import 'track.dart';

/// Strava の書き出し（アカウントのアーカイブ）から取り込んだ運動1件
class StravaActivity {
  StravaActivity({
    required this.id,
    required this.start,
    required this.kind,
    required this.typeLabel,
    required this.name,
    required this.elapsedS,
    required this.movingS,
    required this.distanceM,
    this.elevGainM,
    this.avgHr,
    this.maxHr,
    this.kcal,
    this.maxSpeedMps,
    this.splits = const [],
    this.bestEfforts = const {},
    this.track = const [],
  });

  /// Strava のアクティビティID（無ければファイル名など）
  final String id;
  final DateTime start;
  final ExerciseKind kind;

  /// Strava 上の種目名（Run・Ride など）
  final String typeLabel;
  final String name;
  final double elapsedS;
  final double movingS;
  final double distanceM;
  final double? elevGainM;
  final double? avgHr;
  final int? maxHr;
  final double? kcal;
  final double? maxSpeedMps;
  final List<Split> splits;
  final Map<String, double> bestEfforts;

  /// 間引いた点（地図・グラフ用）
  final List<TrackPoint> track;

  DateTime get end => start.add(Duration(milliseconds: (elapsedS * 1000).round()));
  bool get hasRoute => _hasRoute ?? track.any((p) => p.hasPosition);
  bool? _hasRoute;

  /// 速さをペース（分/km）で表す種目か
  bool get usesPace => kind == ExerciseKind.running || kind == ExerciseKind.walking || kind == ExerciseKind.hiking;

  Map<String, Object?> toDbMap() => {
        'id': id,
        'start_ms': start.millisecondsSinceEpoch,
        'kind': kind.name,
        'type_label': typeLabel,
        'name': name,
        'elapsed_s': elapsedS,
        'moving_s': movingS,
        'distance_m': distanceM,
        'elev_gain_m': elevGainM,
        'avg_hr': avgHr,
        'max_hr': maxHr,
        'kcal': kcal,
        'max_speed': maxSpeedMps,
        'has_route': hasRoute ? 1 : 0,
        'bests_json': jsonEncode(bestEfforts),
        'detail_json': jsonEncode({
          'splits': splits.map((s) => s.toJson()).toList(),
          'track': encodeTrack(track),
        }),
      };

  /// [withDetail] が false なら一覧用（スプリット・点を読まない）
  factory StravaActivity.fromDbMap(Map<String, Object?> m, {bool withDetail = true}) {
    final start = DateTime.fromMillisecondsSinceEpoch((m['start_ms'] as num).toInt());
    var splits = const <Split>[];
    var bests = const <String, double>{};
    var track = const <TrackPoint>[];
    if (m['bests_json'] is String) {
      bests = (jsonDecode(m['bests_json'] as String) as Map? ?? const {})
          .map((k, v) => MapEntry(k as String, (v as num).toDouble()));
    }
    if (withDetail && m['detail_json'] is String) {
      final j = jsonDecode(m['detail_json'] as String) as Map<String, dynamic>;
      splits = (j['splits'] as List? ?? const []).map((e) => Split.fromJson(e as Map<String, dynamic>)).toList();
      track = decodeTrack(j['track'] as List? ?? const [], start);
    }
    double? d(String k) => (m[k] as num?)?.toDouble();
    return StravaActivity(
      id: m['id'] as String,
      start: start,
      kind: ExerciseKind.fromKey(m['kind'] as String?),
      typeLabel: m['type_label'] as String? ?? '',
      name: m['name'] as String? ?? '',
      elapsedS: d('elapsed_s') ?? 0,
      movingS: d('moving_s') ?? 0,
      distanceM: d('distance_m') ?? 0,
      elevGainM: d('elev_gain_m'),
      avgHr: d('avg_hr'),
      maxHr: (m['max_hr'] as num?)?.toInt(),
      kcal: d('kcal'),
      maxSpeedMps: d('max_speed'),
      splits: splits,
      bestEfforts: bests,
      track: track,
    ).._hasRoute = m['has_route'] == null ? null : (m['has_route'] as num) == 1;
  }
}

/// CSV を行・列に分ける（ダブルクォート・改行入りの値に対応）
List<List<String>> parseCsv(String text) {
  if (text.startsWith('﻿')) text = text.substring(1);
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      if (row.length > 1 || row.first.isNotEmpty) rows.add(row);
      row = <String>[];
    } else {
      cell.write(c);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

/// Strava の種目名（英語・日本語）とファイルの種目からアプリの種目へ
ExerciseKind kindFromStrava(String? type, [String? fileSport]) {
  final t = (type ?? '').toLowerCase().replaceAll(' ', '');
  bool has(List<String> keys) => keys.any(t.contains);
  if (t.isNotEmpty) {
    if (has(['trailrun', 'virtualrun', 'run', 'ラン'])) return ExerciseKind.running;
    if (has(['hike', 'ハイキング', 'ハイク'])) return ExerciseKind.hiking;
    if (has(['walk', 'ウォーク', 'ウォーキング', '散歩'])) return ExerciseKind.walking;
    if (has(['ride', 'bike', 'cycl', 'ライド', 'サイクリング', '自転車'])) return ExerciseKind.biking;
    if (has(['swim', 'スイム', '水泳'])) return ExerciseKind.swimming;
    if (has(['weight', 'crossfit', 'ウェイト', '筋トレ'])) return ExerciseKind.strength;
    if (has(['hiit', 'highintensity'])) return ExerciseKind.hiit;
    if (has(['yoga', 'pilates', 'ヨガ', 'ピラティス'])) return ExerciseKind.yoga;
    if (has(['ski', 'snowboard', 'スキー', 'スノーボード', 'スノボ'])) return ExerciseKind.snow;
  }
  final s = (fileSport ?? '').toLowerCase();
  if (s.contains('run') || s == '9') return ExerciseKind.running;
  if (s.contains('hik')) return ExerciseKind.hiking;
  if (s.contains('walk') || s == '10') return ExerciseKind.walking;
  if (s.contains('cycl') || s.contains('bik') || s == '1') return ExerciseKind.biking;
  if (s.contains('swim')) return ExerciseKind.swimming;
  if (s.contains('ski') || s.contains('snow')) return ExerciseKind.snow;
  if (s.contains('training') || s.contains('fitness')) return ExerciseKind.strength;
  return ExerciseKind.other;
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// activities.csv の日時（UTC）。「Nov 8, 2026, 10:30:15 PM」「2026/11/08 22:30:15」「2026年11月8日 22:30:15」などに対応
DateTime? parseStravaDate(String s) {
  final t = s.replaceAll(RegExp(r'[  ]'), ' ').trim();
  if (t.isEmpty) return null;
  final iso = DateTime.tryParse(t);
  if (iso != null) return iso.isUtc ? iso : DateTime.utc(iso.year, iso.month, iso.day, iso.hour, iso.minute, iso.second);
  int h(String hh, String? ampm) {
    var v = int.parse(hh);
    final ap = (ampm ?? '').toUpperCase();
    if ((ap == 'PM' || ap == '午後') && v < 12) v += 12;
    if ((ap == 'AM' || ap == '午前') && v == 12) v = 0;
    return v;
  }

  final en = RegExp(r'([A-Za-z]{3})[a-z]*\.? (\d{1,2}), (\d{4}),? (\d{1,2}):(\d{2}):(\d{2}) ?(AM|PM)?', caseSensitive: false)
      .firstMatch(t);
  if (en != null) {
    final mo = _months[en.group(1)!.toLowerCase()];
    if (mo == null) return null;
    return DateTime.utc(int.parse(en.group(3)!), mo, int.parse(en.group(2)!), h(en.group(4)!, en.group(7)),
        int.parse(en.group(5)!), int.parse(en.group(6)!));
  }
  final num = RegExp(r'(\d{4})[/年.-](\d{1,2})[/月.-](\d{1,2})日?,? *(午前|午後|AM|PM)? *(\d{1,2}):(\d{2}):(\d{2}) *(AM|PM)?')
      .firstMatch(t);
  if (num != null) {
    return DateTime.utc(int.parse(num.group(1)!), int.parse(num.group(2)!), int.parse(num.group(3)!),
        h(num.group(5)!, num.group(4) ?? num.group(8)), int.parse(num.group(6)!), int.parse(num.group(7)!));
  }
  return null;
}

/// activities.csv の列（英語・日本語の見出しに対応。見つからなければ既知の列番号）
class StravaCsvColumns {
  StravaCsvColumns(List<String> header) {
    final h = header.map((e) => e.trim().toLowerCase()).toList();
    int? find(List<String> names, {int occurrence = 0, int? fallback}) {
      var seen = 0;
      for (var i = 0; i < h.length; i++) {
        if (names.contains(h[i])) {
          if (seen == occurrence) return i;
          seen++;
        }
      }
      return fallback;
    }

    id = find(['activity id', 'アクティビティid', 'アクティビティ id'], fallback: 0);
    date = find(['activity date', 'アクティビティの日付', 'アクティビティ日付', '日付'], fallback: 1);
    name = find(['activity name', 'アクティビティ名', 'アクティビティの名前'], fallback: 2);
    type = find(['activity type', 'アクティビティタイプ', 'アクティビティの種類', 'スポーツの種類'], fallback: 3);
    elapsed = find(['elapsed time', '経過時間'], fallback: 5);
    filename = find(['filename', 'ファイル名'], fallback: 12);
    moving = find(['moving time', '移動時間']);
    // 距離は2回出てくる：1回目は km、2回目は m
    distanceKm = find(['distance', '距離'], fallback: 6);
    distanceM = find(['distance', '距離'], occurrence: 1);
    elevGain = find(['elevation gain', '獲得標高', '標高の上昇']);
    maxHr = find(['max heart rate', '最大心拍数']);
    avgHr = find(['average heart rate', '平均心拍数']);
    calories = find(['calories', 'カロリー']);
    maxSpeed = find(['max speed', '最高速度']);
  }

  late final int? id, date, name, type, elapsed, filename, moving, distanceKm, distanceM, elevGain, maxHr, avgHr,
      calories, maxSpeed;
}

/// activities.csv の1行
class StravaCsvRow {
  StravaCsvRow(this.cols, this.cells);

  final StravaCsvColumns cols;
  final List<String> cells;

  String? str(int? i) {
    if (i == null || i >= cells.length) return null;
    final v = cells[i].trim();
    return v.isEmpty ? null : v;
  }

  double? number(int? i) {
    final s = str(i);
    if (s == null) return null;
    return double.tryParse(s.replaceAll(',', ''));
  }

  String? get id => str(cols.id);
  DateTime? get date => str(cols.date) == null ? null : parseStravaDate(str(cols.date)!);
  String get name => str(cols.name) ?? '';
  String get type => str(cols.type) ?? '';
  String? get filename => str(cols.filename);
  double? get elapsed => number(cols.elapsed);
  double? get moving => number(cols.moving);
  double? get distanceM => number(cols.distanceM) ?? (number(cols.distanceKm) == null ? null : number(cols.distanceKm)! * 1000);
  double? get elevGain => number(cols.elevGain);
  double? get maxHr => number(cols.maxHr);
  double? get avgHr => number(cols.avgHr);
  double? get kcal => number(cols.calories);
  double? get maxSpeed => number(cols.maxSpeed);
}

/// CSV の1行（無ければ null）と、運動のファイル（無ければ null）から1件を作る
StravaActivity? buildActivity({StravaCsvRow? row, ParsedActivityFile? file, String? fallbackId}) {
  final pts = normalizeTrack(file?.points ?? const []);
  final kind = kindFromStrava(row?.type, file?.sport);
  final stats = pts.length >= 2 ? computeStats(pts, running: kind == ExerciseKind.running) : null;
  final start = (pts.isNotEmpty ? pts.first.time : null) ?? file?.start ?? row?.date;
  if (start == null) return null;
  final id = row?.id ?? fallbackId;
  if (id == null) return null;
  double? positive(double? v) => (v == null || v <= 0) ? null : v;
  final elapsed = positive(row?.elapsed) ?? stats?.elapsedS ?? 0;
  return StravaActivity(
    id: id,
    start: start.toLocal(),
    kind: kind,
    typeLabel: row?.type ?? file?.sport ?? '',
    name: (row?.name.isNotEmpty == true ? row!.name : file?.name) ?? '',
    elapsedS: elapsed,
    movingS: positive(row?.moving) ?? positive(stats?.movingS) ?? elapsed,
    distanceM: positive(row?.distanceM) ?? stats?.distanceM ?? 0,
    elevGainM: row?.elevGain ?? stats?.elevGainM,
    avgHr: positive(row?.avgHr) ?? stats?.avgHr,
    maxHr: positive(row?.maxHr)?.round() ?? stats?.maxHr,
    kcal: positive(row?.kcal) ?? positive(file?.kcal),
    maxSpeedMps: positive(row?.maxSpeed) ?? stats?.maxSpeedMps,
    splits: stats?.splits ?? const [],
    bestEfforts: stats?.bestEfforts ?? const {},
    track: downsample(pts),
  );
}
