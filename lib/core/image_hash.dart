/// 写真の再利用判定に使う差分ハッシュ（dHash）。同じ料理を同じように撮った写真ならほぼ一致する。
library;

/// 9×8 の明るさ（行優先、0〜255）から 64bit の dHash（16桁の16進）を作る
String dHashFromGray(List<int> gray9x8) {
  if (gray9x8.length != 72) throw ArgumentError('9×8 の画素が必要です');
  final bits = StringBuffer();
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      bits.write(gray9x8[y * 9 + x] > gray9x8[y * 9 + x + 1] ? '1' : '0');
    }
  }
  final s = bits.toString();
  final hex = StringBuffer();
  for (var i = 0; i < 64; i += 4) {
    hex.write(int.parse(s.substring(i, i + 4), radix: 2).toRadixString(16));
  }
  return hex.toString();
}

/// 16進のハッシュ同士の異なるビット数
int hammingHex(String a, String b) {
  if (a.length != b.length) return 64;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    var x = int.parse(a[i], radix: 16) ^ int.parse(b[i], radix: 16);
    while (x != 0) {
      d += x & 1;
      x >>= 1;
    }
  }
  return d;
}

/// RGBA の画素列（9×8）から明るさへ
List<int> grayFromRgba(List<int> rgba) => [
      for (var i = 0; i + 3 < rgba.length; i += 4) ((rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) ~/ 1000),
    ];
