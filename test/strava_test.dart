import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meal_log/core/activity.dart';
import 'package:meal_log/core/activity_files.dart';
import 'package:meal_log/core/strava_archive.dart';
import 'package:meal_log/core/track.dart';

/// 東西方向に約 [stepM] m ずつ進む点（緯度35度）
List<TrackPoint> straightRun({int n = 600, double stepM = 3.5, int secPerPoint = 1, int? hr}) {
  final start = DateTime.utc(2026, 11, 1, 22);
  const lat = 35.0;
  const degPerM = 1 / (111320 * 0.8191520443); // cos(35°)
  return [
    for (var i = 0; i < n; i++)
      TrackPoint(
        time: start.add(Duration(seconds: i * secPerPoint)),
        lat: lat,
        lon: 139.0 + i * stepM * degPerM,
        ele: 10.0 + (i ~/ 100) * 5,
        hr: hr,
      ),
  ];
}

Uint8List buildFit() {
  final b = BytesBuilder();
  void u8(int v) => b.addByte(v);
  void u16(int v) => b.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());
  void u32(int v) => b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void s32(int v) => b.add((ByteData(4)..setInt32(0, v, Endian.little)).buffer.asUint8List());

  // record の定義（ローカル0 → グローバル20）
  u8(0x40);
  u8(0);
  u8(0);
  u16(20);
  u8(5);
  for (final f in [
    [253, 4, 0x86],
    [0, 4, 0x85],
    [1, 4, 0x85],
    [3, 1, 0x02],
    [5, 4, 0x86],
  ]) {
    f.forEach(u8);
  }
  const semi = 2147483648 / 180;
  const ts0 = 1100000000;
  for (var i = 0; i < 3; i++) {
    u8(0x00);
    u32(ts0 + i);
    s32((35.0 * semi).round());
    s32(((139.0 + i * 0.0001) * semi).round());
    u8(140 + i);
    u32(i * 1000); // 10m ずつ（1/100 m 単位）
  }
  // session の定義（ローカル1 → グローバル18）
  u8(0x41);
  u8(0);
  u8(0);
  u16(18);
  u8(2);
  for (final f in [
    [5, 1, 0x00],
    [11, 2, 0x84],
  ]) {
    f.forEach(u8);
  }
  u8(0x01);
  u8(1); // running
  u16(321);
  final data = b.toBytes();

  final out = BytesBuilder();
  final header = ByteData(14)
    ..setUint8(0, 14)
    ..setUint8(1, 0x20)
    ..setUint16(2, 2132, Endian.little)
    ..setUint32(4, data.length, Endian.little);
  final h = header.buffer.asUint8List();
  h.setRange(8, 12, '.FIT'.codeUnits);
  out.add(h);
  out.add(data);
  out.add([0, 0]);
  return out.toBytes();
}

void main() {
  group('トラックの計算', () {
    test('緯度経度から距離を計算する', () {
      final pts = normalizeTrack(straightRun(n: 1001));
      expect(pts.last.dist, closeTo(3500, 20));
    });

    test('1kmごとのスプリット', () {
      final pts = normalizeTrack(straightRun(n: 1001)); // 3.5km・1000秒
      final splits = computeSplits(pts);
      expect(splits.length, 4);
      expect(splits.first.distanceM, closeTo(1000, 5));
      expect(splits.first.paceSecPerKm, closeTo(1000 / 3.5, 3));
      expect(splits.last.distanceM, closeTo(500, 10));
    });

    test('ベスト記録（一定ペース）', () {
      final pts = normalizeTrack(straightRun(n: 1600)); // 約5.6km
      final s = computeStats(pts, running: true);
      expect(s.bestEfforts['1km'], closeTo(1000 / 3.5, 2));
      expect(s.bestEfforts['5km'], closeTo(5000 / 3.5, 3));
      expect(s.bestEfforts.containsKey('10km'), isFalse);
      expect(s.movingS, closeTo(1599, 1));
      expect(s.maxSpeedMps, closeTo(3.5, 0.1));
    });

    test('獲得標高（3mより小さいぶれは数えない）', () {
      final start = DateTime.utc(2026);
      final eles = <double>[10, 11, 10, 12, 15, 14, 20, 19, 25];
      final pts = [
        for (var i = 0; i < eles.length; i++) TrackPoint(time: start.add(Duration(seconds: i)), ele: eles[i]),
      ];
      expect(elevationGain(pts), 15);
    });

    test('心拍ゾーン', () {
      final pts = straightRun(n: 11, hr: 150);
      final z = heartRateZones(pts, 200); // 75% → ゾーン3
      expect(z[2], 10);
      expect(z.fold<double>(0, (a, b) => a + b), 10);
    });

    test('保存用の変換で値が戻る', () {
      final pts = normalizeTrack(straightRun(n: 5, hr: 120));
      final back = decodeTrack(encodeTrack(pts), pts.first.time);
      expect(back.length, 5);
      expect(back[3].hr, 120);
      expect(back[3].lat, closeTo(35.0, 1e-6));
      expect(back[3].dist, closeTo(pts[3].dist!, 0.1));
      expect(back[3].time, pts[3].time);
    });

    test('ペース・時間の表記', () {
      expect(formatPace(312), '5:12');
      expect(formatDuration(3723), '1:02:03');
      expect(formatDuration(754), '12:34');
    });
  });

  group('ファイルの読み取り', () {
    test('GPX（心拍つき）', () {
      const gpx = '''<?xml version="1.0"?>
<gpx creator="StravaGPX"><metadata><time>2026-11-01T22:00:00Z</time></metadata>
<trk><name>朝ラン</name><type>running</type><trkseg>
<trkpt lat="35.0" lon="139.0"><ele>10.2</ele><time>2026-11-01T22:00:00Z</time><extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>120</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions></trkpt>
<trkpt lat="35.0" lon="139.001"><ele>11.0</ele><time>2026-11-01T22:00:30Z</time><extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>130</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions></trkpt>
</trkseg></trk></gpx>''';
      final f = parseGpx(gpx);
      expect(f.points.length, 2);
      expect(f.points[1].hr, 130);
      expect(f.points[1].lon, 139.001);
      expect(f.points[0].ele, 10.2);
      expect(f.sport, 'running');
      expect(f.name, '朝ラン');
      expect(f.start, DateTime.utc(2026, 11, 1, 22));
    });

    test('TCX（距離・心拍・カロリー）', () {
      const tcx = '''<TrainingCenterDatabase><Activities><Activity Sport="Biking"><Id>2026-11-01T22:00:00Z</Id>
<Lap><Calories>150</Calories><Track>
<Trackpoint><Time>2026-11-01T22:00:00Z</Time><Position><LatitudeDegrees>35</LatitudeDegrees><LongitudeDegrees>139</LongitudeDegrees></Position><AltitudeMeters>5</AltitudeMeters><DistanceMeters>0</DistanceMeters><HeartRateBpm><Value>100</Value></HeartRateBpm></Trackpoint>
<Trackpoint><Time>2026-11-01T22:01:00Z</Time><DistanceMeters>400.5</DistanceMeters><HeartRateBpm><Value>110</Value></HeartRateBpm></Trackpoint>
</Track></Lap></Activity></Activities></TrainingCenterDatabase>''';
      final f = parseTcx(tcx);
      expect(f.points.length, 2);
      expect(f.points[1].dist, 400.5);
      expect(f.points[1].hr, 110);
      expect(f.points[0].lat, 35);
      expect(f.sport, 'biking');
      expect(f.kcal, 150);
    });

    test('FIT（record と session）', () {
      final f = parseFit(buildFit());
      expect(f.points.length, 3);
      expect(f.points[0].lat, closeTo(35.0, 1e-6));
      expect(f.points[2].lon, closeTo(139.0002, 1e-6));
      expect(f.points[1].hr, 141);
      expect(f.points[2].dist, 20);
      expect(f.points[0].time, DateTime.utc(1989, 12, 31).add(const Duration(seconds: 1100000000)));
      expect(f.sport, 'running');
      expect(f.kcal, 321);
    });

    test('FIT でないファイルは拒否', () {
      expect(() => parseFit(Uint8List(20)), throwsFormatException);
    });
  });

  group('activities.csv', () {
    test('CSV の分割（クォート・改行入り）', () {
      final rows = parseCsv('a,b,c\r\n1,"x, y","line1\nline2"\n2,"say ""hi""",\n');
      expect(rows.length, 3);
      expect(rows[1], ['1', 'x, y', 'line1\nline2']);
      expect(rows[2], ['2', 'say "hi"', '']);
    });

    test('日時の読み取り', () {
      expect(parseStravaDate('Nov 8, 2026, 10:30:15 PM'), DateTime.utc(2026, 11, 8, 22, 30, 15));
      expect(parseStravaDate('Jan 2, 2025, 12:05:00 AM'), DateTime.utc(2025, 1, 2, 0, 5));
      expect(parseStravaDate('2026/11/08 7:03:09'), DateTime.utc(2026, 11, 8, 7, 3, 9));
      expect(parseStravaDate('2026年11月8日 22:30:15'), DateTime.utc(2026, 11, 8, 22, 30, 15));
      expect(parseStravaDate(''), isNull);
    });

    test('種目の対応', () {
      expect(kindFromStrava('Run'), ExerciseKind.running);
      expect(kindFromStrava('Trail Run'), ExerciseKind.running);
      expect(kindFromStrava('Ride'), ExerciseKind.biking);
      expect(kindFromStrava('ウォーク'), ExerciseKind.walking);
      expect(kindFromStrava('Weight Training'), ExerciseKind.strength);
      expect(kindFromStrava('', 'cycling'), ExerciseKind.biking);
      expect(kindFromStrava(null, null), ExerciseKind.other);
    });

    test('CSV の行から運動を作る（ファイルなし）', () {
      const header =
          'Activity ID,Activity Date,Activity Name,Activity Type,Activity Description,Elapsed Time,Distance,Max Heart Rate,'
          'Relative Effort,Commute,Activity Private Note,Activity Gear,Filename,Athlete Weight,Bike Weight,Elapsed Time,'
          'Moving Time,Distance,Max Speed,Average Speed,Elevation Gain,Elevation Loss,Average Heart Rate,Calories';
      const line = '123,"Nov 1, 2026, 10:00:00 PM",朝ラン,Run,,1800,5.01,175.0,,false,,,activities/123.gpx,,,1800.0,'
          '1750.0,5012.3,4.2,2.86,32.5,30.0,150.5,380.0';
      final rows = parseCsv('$header\n$line\n');
      final row = StravaCsvRow(StravaCsvColumns(rows.first), rows[1]);
      expect(row.filename, 'activities/123.gpx');
      final a = buildActivity(row: row)!;
      expect(a.id, '123');
      expect(a.kind, ExerciseKind.running);
      expect(a.name, '朝ラン');
      expect(a.start.toUtc(), DateTime.utc(2026, 11, 1, 22));
      expect(a.distanceM, 5012.3);
      expect(a.movingS, 1750);
      expect(a.elapsedS, 1800);
      expect(a.elevGainM, 32.5);
      expect(a.avgHr, 150.5);
      expect(a.maxHr, 175);
      expect(a.kcal, 380);
      expect(a.hasRoute, isFalse);
    });

    test('ファイルだけから運動を作り、DB 形式で往復できる', () {
      final file = ParsedActivityFile(points: straightRun(n: 1200, hr: 140), sport: 'running');
      final a = buildActivity(file: file, fallbackId: 'file:a.gpx')!;
      expect(a.kind, ExerciseKind.running);
      expect(a.distanceM, closeTo(4196, 25));
      expect(a.avgHr, 140);
      expect(a.splits.length, 5);
      expect(a.bestEfforts.containsKey('1km'), isTrue);
      expect(a.hasRoute, isTrue);
      final back = StravaActivity.fromDbMap(a.toDbMap());
      expect(back.id, 'file:a.gpx');
      expect(back.splits.length, 5);
      expect(back.bestEfforts['1km'], closeTo(a.bestEfforts['1km']!, 0.01));
      expect(back.track.length, a.track.length);
      expect(back.hasRoute, isTrue);
      final listOnly = StravaActivity.fromDbMap(a.toDbMap(), withDetail: false);
      expect(listOnly.track, isEmpty);
      expect(listOnly.hasRoute, isTrue);
    });
  });
}
