/// API 料金の概算用単価（USD / 100万トークン）。設定画面から編集できる。
class PriceTable {
  const PriceTable({
    this.haikuIn = 1.0,
    this.haikuOut = 5.0,
    this.sonnetIn = 2.0,
    this.sonnetOut = 10.0,
    this.searchUsd = 0.01,
  });

  final double haikuIn;
  final double haikuOut;
  final double sonnetIn;
  final double sonnetOut;

  /// Web検索1回あたり（USD）
  final double searchUsd;

  /// モデルIDに "haiku" を含めば Haiku 単価、それ以外は Sonnet 単価で計算する。
  double costUsd(String model, int inputTokens, int outputTokens, int webSearches) {
    final isHaiku = model.toLowerCase().contains('haiku');
    final pin = isHaiku ? haikuIn : sonnetIn;
    final pout = isHaiku ? haikuOut : sonnetOut;
    return inputTokens / 1e6 * pin + outputTokens / 1e6 * pout + webSearches * searchUsd;
  }
}
