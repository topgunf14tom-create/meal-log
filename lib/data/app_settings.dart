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

  // ヘルスコネクト
  /// 連携を使う（権限を許可した時点で true）
  bool get healthEnabled => _values['health_enabled'] == 'true';

  /// 消費カロリーを目標カロリーに上乗せする（既定オン）
  bool get addBurnToGoal => _values['add_burn_to_goal'] != 'false';

  /// ホームの「連携しませんか」カードを閉じた
  bool get healthPromptDismissed => _values['health_prompt_dismissed'] == 'true';

  /// 手入力の身長（cm）。未設定なら null（ヘルスコネクト・InBody の値を使う）
  double? get heightCm {
    final v = double.tryParse(_values['height_cm'] ?? '');
    return (v == null || v < 80 || v > 250) ? null : v;
  }

  /// ヘルスコネクト・InBody から取得した身長（cm）
  double? get autoHeightCm => double.tryParse(_values['auto_height_cm'] ?? '');

  /// 体重・体脂肪を最後に取り込んだ時刻
  DateTime? get healthBodySyncedAt => DateTime.tryParse(_values['health_body_synced_at'] ?? '');
}
