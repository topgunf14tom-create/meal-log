import 'package:flutter/services.dart';

/// 端末の機能（通知・ホーム画面ウィジェット・ファイルの保存先）。Kotlin 側は MainActivity
class DeviceService {
  static const _ch = MethodChannel('meal_log/health');

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> notificationsAllowed() async => await _call<bool>('notificationsAllowed') ?? false;

  /// Android 13 以降は通知の許可画面を出す
  Future<bool> requestNotifications() async => await _call<bool>('requestNotifications') ?? false;

  Future<void> scheduleReminders(List<Map<String, Object?>> items) async {
    await _call<bool>('scheduleReminders', {'items': items});
  }

  Future<void> updateWidget(Map<String, Object?> data) async {
    await _call<bool>('updateWidget', data);
  }

  /// 保存先のファイルを作ってもらう（Google ドライブも選べる）。{uri, name, provider}
  Future<Map<String, String>?> createBackupFile(String name) async {
    final m = await _ch.invokeMapMethod<String, Object?>('createBackupFile', {'name': name});
    if (m == null) return null;
    return m.map((k, v) => MapEntry(k, v?.toString() ?? ''));
  }

  Future<void> writeUri(String uri, String text) async {
    await _ch.invokeMethod<bool>('writeUri', {'uri': uri, 'text': text});
  }

  /// ファイルを選んで中身（テキスト）を返す
  Future<String?> pickTextFile() => _ch.invokeMethod<String>('pickTextFile');
}
