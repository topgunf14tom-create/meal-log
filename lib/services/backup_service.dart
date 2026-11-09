import 'dart:convert';

import '../data/app_db.dart';
import '../data/app_settings.dart';
import 'device_service.dart';

/// 毎日の自動バックアップ。保存先は利用者が選んだファイル（Google ドライブなど）で、
/// アプリを開いたときに前回から20時間以上たっていれば上書き保存する
class BackupService {
  BackupService({required this.db, required this.settings, required this.device});

  final AppDb db;
  final AppSettings settings;
  final DeviceService device;

  static const _uriKey = 'backup_uri';
  static const _nameKey = 'backup_name';
  static const _providerKey = 'backup_provider';
  static const _lastKey = 'backup_last';
  static const _errorKey = 'backup_error';

  String? get uri => _nonEmpty(settings.raw(_uriKey));
  String? get name => _nonEmpty(settings.raw(_nameKey));
  DateTime? get lastBackup => DateTime.tryParse(settings.raw(_lastKey) ?? '');
  String? get lastError => _nonEmpty(settings.raw(_errorKey));
  bool get enabled => uri != null;

  /// Google ドライブに保存しているか
  bool get onGoogleDrive => (settings.raw(_providerKey) ?? '').contains('google.android.apps.docs');

  static String? _nonEmpty(String? s) => (s == null || s.trim().isEmpty) ? null : s;

  /// 保存先を選んで、すぐ1回保存する。選ばなければ false
  Future<bool> chooseLocation() async {
    final r = await device.createBackupFile('meal-log-backup.json');
    if (r == null || (r['uri'] ?? '').isEmpty) return false;
    await settings.set(_uriKey, r['uri']!);
    await settings.set(_nameKey, r['name'] ?? '');
    await settings.set(_providerKey, r['provider'] ?? '');
    await backupNow();
    return true;
  }

  Future<void> turnOff() async {
    await settings.remove(_uriKey);
    await settings.remove(_nameKey);
    await settings.remove(_providerKey);
  }

  /// 今すぐ保存（失敗したら例外。理由は lastError にも残す）
  Future<void> backupNow() async {
    final u = uri;
    if (u == null) throw StateError('保存先が選ばれていません');
    try {
      final data = await db.exportAll();
      await device.writeUri(u, jsonEncode(data));
      await settings.set(_lastKey, DateTime.now().toIso8601String());
      await settings.remove(_errorKey);
    } catch (e) {
      await settings.set(_errorKey, '${DateTime.now().toIso8601String().substring(0, 16)} $e');
      rethrow;
    }
  }

  /// 前回から20時間以上たっていれば保存（失敗しても例外にしない）
  Future<void> autoBackupIfDue() async {
    if (!enabled) return;
    final last = lastBackup;
    if (last != null && DateTime.now().difference(last) < const Duration(hours: 20)) return;
    try {
      await backupNow();
    } catch (_) {
      // lastError に残っている。設定画面で表示する
    }
  }

  /// バックアップのファイルを選んで、今のデータをすべて置き換える
  Future<bool> restoreFromFile() async {
    final text = await device.pickTextFile();
    if (text == null) return false;
    final data = jsonDecode(text);
    if (data is! Map<String, dynamic>) throw const FormatException('バックアップのファイルではありません');
    await db.importAll(data);
    return true;
  }
}
