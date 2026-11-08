import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Anthropic APIキーを端末の安全な領域（Android Keystore / iOS Keychain）に保存する
class KeyStore {
  static const _key = 'anthropic_api_key';
  final _storage = const FlutterSecureStorage();

  Future<String?> read() async {
    try {
      final v = await _storage.read(key: _key);
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      // 再インストール直後などで復号に失敗した場合は未設定扱い
      return null;
    }
  }

  Future<bool> hasKey() async => (await read()) != null;

  Future<void> write(String value) => _storage.write(key: _key, value: value);

  Future<void> delete() => _storage.delete(key: _key);
}
