import 'dart:typed_data';

import 'track.dart';

/// GPX・TCX・FIT を読んだ結果
class ParsedActivityFile {
  ParsedActivityFile({required this.points, this.sport, this.name, this.kcal, this.start});

  final List<TrackPoint> points;

  /// ファイルに書かれた種目（running / cycling など。小文字）
  final String? sport;
  final String? name;
  final double? kcal;
  final DateTime? start;
}

String? _tag(String block, String name) {
  final m = RegExp('<(?:[A-Za-z0-9_]+:)?$name(?:\\s[^>]*)?>([^<]*)</(?:[A-Za-z0-9_]+:)?$name>').firstMatch(block);
  return m?.group(1)?.trim();
}

double? _num(String? s) => s == null ? null : double.tryParse(s);

DateTime? _time(String? s) {
  if (s == null) return null;
  return DateTime.tryParse(s)?.toUtc();
}

/// GPX（Strava のアプリで記録したものなど）
ParsedActivityFile parseGpx(String xml) {
  final points = <TrackPoint>[];
  final re = RegExp(r'<trkpt\b([^>]*)>(.*?)</trkpt>', dotAll: true);
  for (final m in re.allMatches(xml)) {
    final attrs = m.group(1)!;
    final body = m.group(2)!;
    final lat = _num(RegExp(r'lat="([^"]+)"').firstMatch(attrs)?.group(1));
    final lon = _num(RegExp(r'lon="([^"]+)"').firstMatch(attrs)?.group(1));
    final t = _time(_tag(body, 'time'));
    if (t == null) continue;
    points.add(TrackPoint(
      time: t,
      lat: lat,
      lon: lon,
      ele: _num(_tag(body, 'ele')),
      hr: _num(_tag(body, 'hr'))?.round(),
    ));
  }
  final trk = RegExp(r'<trk>(.*?)<trkseg', dotAll: true).firstMatch(xml)?.group(1) ?? '';
  return ParsedActivityFile(
    points: points,
    sport: _tag(trk, 'type')?.toLowerCase(),
    name: _tag(trk, 'name'),
    start: points.isEmpty ? _time(_tag(xml, 'time')) : points.first.time,
  );
}

/// TCX（Garmin など）
ParsedActivityFile parseTcx(String xml) {
  final points = <TrackPoint>[];
  final re = RegExp(r'<Trackpoint>(.*?)</Trackpoint>', dotAll: true);
  for (final m in re.allMatches(xml)) {
    final body = m.group(1)!;
    final t = _time(_tag(body, 'Time'));
    if (t == null) continue;
    final hrBlock = RegExp(r'<HeartRateBpm[^>]*>(.*?)</HeartRateBpm>', dotAll: true).firstMatch(body)?.group(1);
    points.add(TrackPoint(
      time: t,
      lat: _num(_tag(body, 'LatitudeDegrees')),
      lon: _num(_tag(body, 'LongitudeDegrees')),
      ele: _num(_tag(body, 'AltitudeMeters')),
      hr: hrBlock == null ? null : _num(_tag(hrBlock, 'Value'))?.round(),
      dist: _num(_tag(body, 'DistanceMeters')),
    ));
  }
  final sport = RegExp(r'<Activity\s+Sport="([^"]+)"').firstMatch(xml)?.group(1)?.toLowerCase();
  double kcal = 0;
  for (final m in RegExp(r'<Calories>([^<]+)</Calories>').allMatches(xml)) {
    kcal += double.tryParse(m.group(1)!.trim()) ?? 0;
  }
  return ParsedActivityFile(
    points: points,
    sport: sport,
    kcal: kcal > 0 ? kcal : null,
    start: points.isEmpty ? _time(_tag(xml, 'Id')) : points.first.time,
  );
}

class _FitField {
  const _FitField(this.num, this.size, this.baseType);
  final int num;
  final int size;
  final int baseType;
}

class _FitDef {
  _FitDef(this.global, this.littleEndian, this.fields, this.devSize);
  final int global;
  final bool littleEndian;
  final List<_FitField> fields;
  final int devSize;
}

/// FIT の基準時刻（1989-12-31 00:00 UTC）
final _fitEpoch = DateTime.utc(1989, 12, 31);

const _fitSports = {
  1: 'running',
  2: 'cycling',
  5: 'swimming',
  10: 'training',
  11: 'walking',
  13: 'alpine_skiing',
  14: 'snowboarding',
  17: 'hiking',
  4: 'fitness_equipment',
};

/// FIT（Garmin・Wahoo など）の record（位置・心拍・距離）と session（種目・カロリー）を読む
ParsedActivityFile parseFit(Uint8List bytes) {
  if (bytes.length < 14) throw const FormatException('FIT ファイルが短すぎます');
  final bd = ByteData.sublistView(bytes);
  final headerSize = bytes[0];
  if (String.fromCharCodes(bytes.sublist(8, 12)) != '.FIT') {
    throw const FormatException('FIT ファイルではありません');
  }
  final dataSize = bd.getUint32(4, Endian.little);
  var pos = headerSize;
  final end = (headerSize + dataSize).clamp(0, bytes.length);
  final defs = <int, _FitDef>{};
  final points = <TrackPoint>[];
  String? sport;
  double? kcal;
  DateTime? start;
  int lastTs = 0;

  int? readInt(int at, int size, int baseType, bool le) {
    final e = le ? Endian.little : Endian.big;
    final signed = baseType == 0x83 || baseType == 0x85 || baseType == 0x01;
    switch (size) {
      case 1:
        final v = signed ? bd.getInt8(at) : bd.getUint8(at);
        if (!signed && v == 0xFF) return null;
        if (signed && v == 0x7F) return null;
        return v;
      case 2:
        final v = signed ? bd.getInt16(at, e) : bd.getUint16(at, e);
        if (!signed && v == 0xFFFF) return null;
        if (signed && v == 0x7FFF) return null;
        return v;
      case 4:
        final v = signed ? bd.getInt32(at, e) : bd.getUint32(at, e);
        if (!signed && v == 0xFFFFFFFF) return null;
        if (signed && v == 0x7FFFFFFF) return null;
        return v;
      default:
        return null;
    }
  }

  while (pos < end) {
    final header = bytes[pos++];
    int local;
    int? compressedTs;
    if (header & 0x80 != 0) {
      local = (header >> 5) & 0x03;
      final offset = header & 0x1F;
      var ts = (lastTs & ~0x1F) + offset;
      if (offset < (lastTs & 0x1F)) ts += 0x20;
      compressedTs = ts;
      lastTs = ts;
    } else if (header & 0x40 != 0) {
      // 定義メッセージ
      local = header & 0x0F;
      final hasDev = header & 0x20 != 0;
      if (pos + 5 > end) break;
      final le = bytes[pos + 1] == 0;
      final global = le ? bd.getUint16(pos + 2, Endian.little) : bd.getUint16(pos + 2, Endian.big);
      final n = bytes[pos + 4];
      pos += 5;
      final fields = <_FitField>[];
      for (var i = 0; i < n; i++) {
        fields.add(_FitField(bytes[pos], bytes[pos + 1], bytes[pos + 2]));
        pos += 3;
      }
      var devSize = 0;
      if (hasDev) {
        final dn = bytes[pos++];
        for (var i = 0; i < dn; i++) {
          devSize += bytes[pos + 1];
          pos += 3;
        }
      }
      defs[local] = _FitDef(global, le, fields, devSize);
      continue;
    } else {
      local = header & 0x0F;
    }
    final def = defs[local];
    if (def == null) throw const FormatException('FIT の定義が見つかりません');
    final values = <int, int?>{};
    for (final f in def.fields) {
      if (pos + f.size > end) break;
      values[f.num] = (f.size == 1 || f.size == 2 || f.size == 4) ? readInt(pos, f.size, f.baseType, def.littleEndian) : null;
      pos += f.size;
    }
    pos += def.devSize;

    final ts = values[253];
    if (ts != null) lastTs = ts;
    final tsAll = ts ?? compressedTs;

    if (def.global == 20 && tsAll != null) {
      // record
      final lat = values[0];
      final lon = values[1];
      const semi = 180 / 2147483648;
      final alt = values[78] ?? values[2];
      final dist = values[5];
      points.add(TrackPoint(
        time: _fitEpoch.add(Duration(seconds: tsAll)),
        lat: lat == null ? null : lat * semi,
        lon: lon == null ? null : lon * semi,
        ele: alt == null ? null : alt / 5 - 500,
        hr: values[3],
        dist: dist == null ? null : dist / 100,
      ));
    } else if (def.global == 18) {
      // session
      final sp = values[5];
      if (sp != null) sport ??= _fitSports[sp] ?? 'other';
      final c = values[11];
      if (c != null) kcal = (kcal ?? 0) + c;
      final st = values[2];
      if (st != null) start ??= _fitEpoch.add(Duration(seconds: st));
    } else if (def.global == 12 && sport == null) {
      // sport
      final sp = values[0];
      if (sp != null) sport = _fitSports[sp] ?? 'other';
    }
  }
  return ParsedActivityFile(
    points: points,
    sport: sport,
    kcal: kcal,
    start: start ?? (points.isEmpty ? null : points.first.time),
  );
}
