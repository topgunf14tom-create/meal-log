import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';

import '../core/activity_files.dart';
import '../core/strava_archive.dart';

/// 取り込み結果
class StravaImportResult {
  const StravaImportResult({required this.activities, required this.skipped, required this.errors});

  /// DB にそのまま入れられる形（別スレッドから受け渡すため Map）
  final List<Map<String, Object?>> activities;
  final int skipped;
  final List<String> errors;
}

/// システムのファイル選択画面で Strava の書き出し（zip・csv・gpx・tcx・fit）を選ぶ。
/// 選ばれたファイルはアプリのキャッシュにコピーされ、そのパスを返す
Future<String?> pickImportFile() async {
  const ch = MethodChannel('meal_log/health');
  final m = await ch.invokeMapMethod<String, Object?>('pickFile');
  return m?['path'] as String?;
}

/// 取り込みは重いので別スレッドで行う
Future<StravaImportResult> importStravaFile(String path) => Isolate.run(() => _import(path));

ParsedActivityFile? _parseFile(String name, Uint8List bytes) {
  var n = name.toLowerCase();
  var data = bytes;
  if (n.endsWith('.gz')) {
    data = GZipDecoder().decodeBytes(data);
    n = n.substring(0, n.length - 3);
  }
  if (n.endsWith('.gpx')) return parseGpx(utf8.decode(data, allowMalformed: true));
  if (n.endsWith('.tcx')) return parseTcx(utf8.decode(data, allowMalformed: true).trimLeft());
  if (n.endsWith('.fit')) return parseFit(data);
  return null;
}

StravaImportResult _import(String path) {
  final lower = path.toLowerCase();
  final out = <Map<String, Object?>>[];
  final errors = <String>[];
  var skipped = 0;

  void addRows(String csv, ParsedActivityFile? Function(String filename)? fileFor) {
    final rows = parseCsv(csv);
    if (rows.isEmpty) return;
    final cols = StravaCsvColumns(rows.first);
    for (final cells in rows.skip(1)) {
      final row = StravaCsvRow(cols, cells);
      ParsedActivityFile? file;
      final fn = row.filename;
      if (fn != null && fileFor != null) {
        try {
          file = fileFor(fn);
        } catch (e) {
          if (errors.length < 5) errors.add('$fn：$e');
        }
      }
      final a = buildActivity(row: row, file: file);
      if (a == null) {
        skipped++;
      } else {
        out.add(a.toDbMap());
      }
    }
  }

  if (lower.endsWith('.zip')) {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final byName = <String, ArchiveFile>{};
      ArchiveFile? csv;
      for (final f in archive.files) {
        if (!f.isFile) continue;
        byName[f.name] = f;
        final n = f.name.toLowerCase();
        if (n.endsWith('activities.csv') && (csv == null || f.name.length < csv.name.length)) csv = f;
      }
      if (csv != null) {
        final text = utf8.decode(csv.readBytes() ?? Uint8List(0), allowMalformed: true);
        addRows(text, (fn) {
          final f = byName[fn] ?? byName.entries.where((e) => e.key.endsWith(fn)).map((e) => e.value).firstOrNull;
          final bytes = f?.readBytes();
          if (f == null || bytes == null) return null;
          final parsed = _parseFile(f.name, bytes);
          f.closeSync();
          return parsed;
        });
      } else {
        // activities.csv が無い zip：中の運動ファイルをすべて読む
        for (final f in byName.values) {
          try {
            final bytes = f.readBytes();
            if (bytes == null) continue;
            final parsed = _parseFile(f.name, bytes);
            if (parsed == null) continue;
            final a = buildActivity(file: parsed, fallbackId: 'file:${f.name.split('/').last}');
            if (a == null) {
              skipped++;
            } else {
              out.add(a.toDbMap());
            }
          } catch (e) {
            skipped++;
            if (errors.length < 5) errors.add('${f.name}：$e');
          }
        }
      }
    } finally {
      input.closeSync();
    }
  } else if (lower.endsWith('.csv')) {
    addRows(utf8.decode(File(path).readAsBytesSync(), allowMalformed: true), null);
  } else {
    final name = path.split('/').last;
    final parsed = _parseFile(name, File(path).readAsBytesSync());
    if (parsed == null) {
      throw const FormatException('対応していないファイルです（zip・csv・gpx・tcx・fit に対応）');
    }
    final a = buildActivity(file: parsed, fallbackId: 'file:$name');
    if (a == null) {
      skipped++;
    } else {
      out.add(a.toDbMap());
    }
  }
  try {
    File(path).deleteSync();
  } catch (_) {}
  return StravaImportResult(activities: out, skipped: skipped, errors: errors);
}
