import 'dart:math' as math;

/// 運動の記録の1点（GPX・TCX・FIT から読み取ったもの）
class TrackPoint {
  const TrackPoint({
    required this.time,
    this.lat,
    this.lon,
    this.ele,
    this.hr,
    this.dist,
  });

  final DateTime time;
  final double? lat;
  final double? lon;

  /// 標高（m）
  final double? ele;

  /// 心拍数（bpm）
  final int? hr;

  /// 開始からの累積距離（m）。ファイルに無ければ緯度経度から計算する
  final double? dist;

  bool get hasPosition => lat != null && lon != null;

  TrackPoint copyWith({double? dist}) =>
      TrackPoint(time: time, lat: lat, lon: lon, ele: ele, hr: hr, dist: dist ?? this.dist);
}

/// 2点間の距離（m、ハーバーサイン）
double haversineM(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371008.8;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(a)));
}

/// 時刻順に並べ、累積距離をそろえる（ファイルに距離が無い点は緯度経度から計算）
List<TrackPoint> normalizeTrack(List<TrackPoint> raw) {
  final pts = [...raw]..sort((a, b) => a.time.compareTo(b.time));
  if (pts.isEmpty) return pts;
  final hasFileDist = pts.where((p) => p.dist != null).length >= pts.length * 0.5;
  final out = <TrackPoint>[];
  double acc = 0;
  TrackPoint? lastPos;
  double lastFileDist = 0;
  for (final p in pts) {
    if (hasFileDist) {
      final d = p.dist ?? lastFileDist;
      lastFileDist = math.max(lastFileDist, d);
      out.add(p.copyWith(dist: lastFileDist));
      continue;
    }
    if (p.hasPosition) {
      if (lastPos != null) {
        final step = haversineM(lastPos.lat!, lastPos.lon!, p.lat!, p.lon!);
        // GPS の飛び（1秒で100m超など）は無視
        final sec = p.time.difference(lastPos.time).inMilliseconds / 1000;
        if (sec <= 0 || step / math.max(sec, 1) < 100) acc += step;
      }
      lastPos = p;
    }
    out.add(p.copyWith(dist: acc));
  }
  return out;
}

/// 1kmごとのスプリット
class Split {
  const Split({
    required this.index,
    required this.distanceM,
    required this.seconds,
    this.eleDiff,
    this.avgHr,
  });

  final int index;
  final double distanceM;
  final double seconds;
  final double? eleDiff;
  final double? avgHr;

  /// 1kmあたりの秒数
  double get paceSecPerKm => distanceM <= 0 ? 0 : seconds / distanceM * 1000;

  Map<String, Object?> toJson() => {'i': index, 'd': distanceM, 's': seconds, 'e': eleDiff, 'h': avgHr};

  factory Split.fromJson(Map<String, dynamic> j) => Split(
        index: (j['i'] as num).toInt(),
        distanceM: (j['d'] as num).toDouble(),
        seconds: (j['s'] as num).toDouble(),
        eleDiff: (j['e'] as num?)?.toDouble(),
        avgHr: (j['h'] as num?)?.toDouble(),
      );
}

/// ベスト記録の距離（ランニング）
const bestEffortDistances = <(String, double)>[
  ('400m', 400),
  ('1km', 1000),
  ('1マイル', 1609.344),
  ('5km', 5000),
  ('10km', 10000),
  ('ハーフ', 21097.5),
  ('フル', 42195),
];

/// トラックから計算した集計値
class TrackStats {
  const TrackStats({
    required this.distanceM,
    required this.elapsedS,
    required this.movingS,
    this.elevGainM,
    this.avgHr,
    this.maxHr,
    this.maxSpeedMps,
    this.splits = const [],
    this.bestEfforts = const {},
  });

  final double distanceM;
  final double elapsedS;
  final double movingS;
  final double? elevGainM;
  final double? avgHr;
  final int? maxHr;
  final double? maxSpeedMps;
  final List<Split> splits;

  /// 距離ラベル → 最速の秒数（ランニングのみ）
  final Map<String, double> bestEfforts;
}

/// 標高の獲得（3m のヒステリシスで GPS のぶれを除く）
double? elevationGain(List<TrackPoint> pts) {
  final eles = pts.map((p) => p.ele).whereType<double>().toList();
  if (eles.length < 2) return null;
  double gain = 0;
  var ref = eles.first;
  for (final e in eles.skip(1)) {
    if (e - ref >= 3) {
      gain += e - ref;
      ref = e;
    } else if (ref - e >= 3) {
      ref = e;
    }
  }
  return gain;
}

/// 移動時間：速度 0.5m/s 未満の区間と、10秒を超える記録の途切れを除く
double movingSeconds(List<TrackPoint> pts) {
  double t = 0;
  for (var i = 1; i < pts.length; i++) {
    final dt = pts[i].time.difference(pts[i - 1].time).inMilliseconds / 1000;
    if (dt <= 0) continue;
    final dd = (pts[i].dist ?? 0) - (pts[i - 1].dist ?? 0);
    if (dt > 10 && dd / dt < 0.5) continue;
    if (dd / dt >= 0.5) t += dt;
  }
  return t;
}

/// 1kmごとのスプリット（最後の1km未満も含める）
List<Split> computeSplits(List<TrackPoint> pts, {double unitM = 1000}) {
  if (pts.length < 2) return const [];
  final splits = <Split>[];
  var startIdx = 0;
  var next = unitM;
  final total = pts.last.dist ?? 0;
  for (var i = 1; i < pts.length; i++) {
    final d = pts[i].dist ?? 0;
    final isLast = i == pts.length - 1;
    if (d >= next || (isLast && d - (pts[startIdx].dist ?? 0) >= 50)) {
      final seg = pts.sublist(startIdx, i + 1);
      final hrs = seg.map((p) => p.hr).whereType<int>().toList();
      final e0 = seg.firstWhere((p) => p.ele != null, orElse: () => seg.first).ele;
      final e1 = seg.lastWhere((p) => p.ele != null, orElse: () => seg.last).ele;
      splits.add(Split(
        index: splits.length + 1,
        distanceM: d - (pts[startIdx].dist ?? 0),
        seconds: pts[i].time.difference(pts[startIdx].time).inMilliseconds / 1000,
        eleDiff: (e0 != null && e1 != null) ? e1 - e0 : null,
        avgHr: hrs.isEmpty ? null : hrs.reduce((a, b) => a + b) / hrs.length,
      ));
      startIdx = i;
      next = (d ~/ unitM + 1) * unitM;
      if (next > total + unitM) break;
    }
  }
  return splits;
}

/// 指定した距離を走るのにかかった最短の秒数（区間を滑らせて探す）
double? bestEffortSeconds(List<TrackPoint> pts, double distanceM) {
  if (pts.length < 2 || (pts.last.dist ?? 0) < distanceM) return null;
  double? best;
  var j = 0;
  for (var i = 0; i < pts.length; i++) {
    final startD = pts[i].dist ?? 0;
    while (j < pts.length && (pts[j].dist ?? 0) - startD < distanceM) {
      j++;
    }
    if (j >= pts.length) break;
    // 距離ちょうどの時刻を線形補間
    final dj = pts[j].dist ?? 0;
    final dj0 = pts[j - 1].dist ?? 0;
    final tj = pts[j].time.millisecondsSinceEpoch / 1000;
    final tj0 = pts[j - 1].time.millisecondsSinceEpoch / 1000;
    final target = startD + distanceM;
    final tEnd = dj == dj0 ? tj : tj0 + (tj - tj0) * (target - dj0) / (dj - dj0);
    final sec = tEnd - pts[i].time.millisecondsSinceEpoch / 1000;
    if (sec > 0 && (best == null || sec < best)) best = sec;
  }
  return best;
}

TrackStats computeStats(List<TrackPoint> pts, {bool running = false}) {
  if (pts.isEmpty) {
    return const TrackStats(distanceM: 0, elapsedS: 0, movingS: 0);
  }
  final hrs = pts.map((p) => p.hr).whereType<int>().where((h) => h > 30 && h < 240).toList();
  double? maxSpeed;
  // 最高速度：10秒以上の区間で平均した速度の最大（GPS のぶれ対策）
  var j = 0;
  for (var i = 0; i < pts.length; i++) {
    while (j < pts.length && pts[j].time.difference(pts[i].time).inSeconds < 10) {
      j++;
    }
    if (j >= pts.length) break;
    final dt = pts[j].time.difference(pts[i].time).inMilliseconds / 1000;
    final v = ((pts[j].dist ?? 0) - (pts[i].dist ?? 0)) / dt;
    if (v < 60 && (maxSpeed == null || v > maxSpeed)) maxSpeed = v;
  }
  final bests = <String, double>{};
  if (running) {
    for (final (label, d) in bestEffortDistances) {
      final s = bestEffortSeconds(pts, d);
      if (s != null) bests[label] = s;
    }
  }
  return TrackStats(
    distanceM: pts.last.dist ?? 0,
    elapsedS: pts.last.time.difference(pts.first.time).inMilliseconds / 1000,
    movingS: movingSeconds(pts),
    elevGainM: elevationGain(pts),
    avgHr: hrs.isEmpty ? null : hrs.reduce((a, b) => a + b) / hrs.length,
    maxHr: hrs.isEmpty ? null : hrs.reduce(math.max),
    maxSpeedMps: maxSpeed,
    splits: computeSplits(pts),
    bestEfforts: bests,
  );
}

/// 保存用に点を間引く（最大 [maxPoints] 点。最初と最後は残す）
List<TrackPoint> downsample(List<TrackPoint> pts, {int maxPoints = 1500}) {
  if (pts.length <= maxPoints) return pts;
  final step = pts.length / maxPoints;
  final out = <TrackPoint>[];
  for (var i = 0.0; i < pts.length; i += step) {
    out.add(pts[i.floor()]);
  }
  if (out.last != pts.last) out.add(pts.last);
  return out;
}

/// 保存用：[開始からの秒, 緯度, 経度, 標高, 心拍, 距離] の配列
List<List<num?>> encodeTrack(List<TrackPoint> pts) {
  if (pts.isEmpty) return const [];
  final t0 = pts.first.time;
  double? r(double? v, int digits) => v == null ? null : double.parse(v.toStringAsFixed(digits));
  return [
    for (final p in pts)
      [
        p.time.difference(t0).inMilliseconds / 1000,
        r(p.lat, 6),
        r(p.lon, 6),
        r(p.ele, 1),
        p.hr,
        r(p.dist, 1),
      ],
  ];
}

List<TrackPoint> decodeTrack(List<dynamic> raw, DateTime start) => [
      for (final e in raw)
        if (e is List && e.length >= 6)
          TrackPoint(
            time: start.add(Duration(milliseconds: ((e[0] as num) * 1000).round())),
            lat: (e[1] as num?)?.toDouble(),
            lon: (e[2] as num?)?.toDouble(),
            ele: (e[3] as num?)?.toDouble(),
            hr: (e[4] as num?)?.toInt(),
            dist: (e[5] as num?)?.toDouble(),
          ),
    ];

/// 心拍ゾーン（最大心拍に対する割合：〜60, 60〜70, 70〜80, 80〜90, 90〜%）ごとの秒数
List<double> heartRateZones(List<TrackPoint> pts, int maxHr) {
  final zones = List<double>.filled(5, 0);
  for (var i = 1; i < pts.length; i++) {
    final hr = pts[i].hr;
    if (hr == null) continue;
    final dt = pts[i].time.difference(pts[i - 1].time).inMilliseconds / 1000;
    if (dt <= 0 || dt > 30) continue;
    final pct = hr / maxHr;
    final z = pct < 0.6 ? 0 : pct < 0.7 ? 1 : pct < 0.8 ? 2 : pct < 0.9 ? 3 : 4;
    zones[z] += dt;
  }
  return zones;
}

/// 「5:12 /km」のようなペース表記
String formatPace(double secPerKm) {
  if (!secPerKm.isFinite || secPerKm <= 0) return '−';
  final s = secPerKm.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// 「1:02:03」「12:34」のような時間表記
String formatDuration(double seconds) {
  final s = seconds.round();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  return '$m:${sec.toString().padLeft(2, '0')}';
}
