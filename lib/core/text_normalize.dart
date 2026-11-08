/// チェーン店キャッシュ用のキー正規化：全角英数記号→半角、空白除去、小文字化
String normalizeKey(String s) {
  final b = StringBuffer();
  for (final rune in s.runes) {
    var c = rune;
    if (c >= 0xFF01 && c <= 0xFF5E) c -= 0xFEE0; // 全角ASCII → 半角
    if (c == 0x3000) continue; // 全角スペース
    final ch = String.fromCharCode(c);
    if (ch.trim().isEmpty) continue;
    b.write(ch);
  }
  return b.toString().toLowerCase();
}
