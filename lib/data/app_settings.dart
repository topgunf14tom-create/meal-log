import '../core/models.dart';
import '../core/pricing.dart';
import 'app_db.dart';

/// APIキー以外の設定（端末内DBの settings テーブルに保存）
class AppSettings {
  AppSettings._(this._db, this._values);

  final AppDb _db;
  final Map<String, String> _values;

  static Future<AppSettings> load(AppDb db) async => AppSettings._(db, Map.of(await db.allSettings()));

  String _s(String key, String fallback) {
    final v = _values[key];
    return (v == null || v.trim().isEmpty) ? fallback : v.trim();
  }

  double _d(String key, double fallback) => double.tryParse(_values[key] ?? '') ?? fallback;
  int _i(String key, int fallback) => int.tryParse(_values[key] ?? '') ?? fallback;

  Future<void> set(String key, Object value) async {
    _values[key] = value.toString();
    await _db.setSetting(key, value.toString());
  }

  // モデル
  String get photoModel => _s('photo_model', ModelIds.photoDefault);
  String get chainModel => _s('chain_model', ModelIds.chainDefault);
  String get reanalyzeModel => _s('reanalyze_model', ModelIds.reanalyzeDefault);

  // 画像圧縮
  int get maxSide => _i('max_side', 1024);
  int get jpegQuality => _i('jpeg_quality', 80);

  // 料金
  double get fxRate => _d('fx_rate', 150);
  PriceTable get prices => PriceTable(
        haikuIn: _d('price_haiku_in', 1.0),
        haikuOut: _d('price_haiku_out', 5.0),
        sonnetIn: _d('price_sonnet_in', 2.0),
        sonnetOut: _d('price_sonnet_out', 10.0),
        searchUsd: _d('price_search', 0.01),
      );

  // 初回案内
  bool get onboardingDone => _values['onboarding_done'] == 'true';
}
