/// 整数なら整数表記、それ以外は小数1桁
String fmtNum(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(1);
}

/// g 表示用（小数1桁）
String g1(double v) => v.toStringAsFixed(1);

/// kcal 表示用（整数）
String kcal0(double v) => v.round().toString();
