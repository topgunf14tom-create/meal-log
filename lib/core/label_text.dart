/// 栄養成分表示の文字（端末OCRの結果）から数値を取り出す。取り出せないときは Haiku の転記に回す。
library;

import 'dart:convert';
import 'dart:math' as math;

import 'portion.dart';

class LabelValues {
  const LabelValues({
    this.name,
    this.kcal,
    this.protein,
    this.fat,
    this.carbs,
    this.salt,
    this.unitLabel,
    this.unitGrams,
    this.per100,
  });

  final String? name;
  final double? kcal;
  final double? protein;
  final double? fat;
  final double? carbs;
  final double? salt;

  /// 表示単位（「1袋」「1個」など）
  final String? unitLabel;

  /// 表示単位の重さ（「1袋（45g）当たり」の 45）
  final double? unitGrams;

  /// 100g（100ml）当たりの表示
  final bool? per100;

  bool get complete => kcal != null && protein != null && fat != null && carbs != null;

  /// 4項目そろい、kcal ≒ P×4＋F×9＋C×4 が成り立つ
  bool get consistent => complete && atwaterOk(kcal!, protein!, fat!, carbs!);
}

String _halfwidth(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    var c = r;
    if (c >= 0xFF01 && c <= 0xFF5E) c -= 0xFEE0;
    if (c == 0x3000) c = 0x20;
    b.writeCharCode(c);
  }
  // OCR で出やすい読み違い
  return b
      .toString()
      .replaceAll('，', '.')
      .replaceAll(RegExp(r'(?<=\d)[,，](?=\d)'), '.')
      .replaceAll(RegExp(r'(?<=\d)\s+\.(?=\d)'), '.')
      .replaceAll('kca1', 'kcal')
      .replaceAll('Kcal', 'kcal');
}

final _num = RegExp(r'(\d+(?:\.\d+)?)');

/// どれかの項目名
final _anyLabel = RegExp(r'エネルギー|熱量|たんぱく質|タンパク質|蛋白質|脂質|炭水化物|糖質|食物繊維|食塩');

/// 項目名の直後（改行をまたいで24文字以内、次の項目名より前）にある最初の数値
double? _after(String t, RegExp label) {
  final m = label.firstMatch(t);
  if (m == null) return null;
  var rest = t.substring(m.end, math.min(m.end + 24, t.length));
  final next = _anyLabel.firstMatch(rest);
  if (next != null) rest = rest.substring(0, next.start);
  final n = _num.firstMatch(rest);
  return n == null ? null : double.tryParse(n.group(1)!);
}

final _kcalLabel = RegExp(r'(エネルギー|熱量|エネルギ一)');
final _protLabel = RegExp(r'(たんぱく質|タンパク質|蛋白質|たんぱく貿|たんばく質)');
final _fatLabel = RegExp(r'脂質');
final _carbLabel = RegExp(r'炭水化物');
final _sugarLabel = RegExp(r'糖質');
final _fiberLabel = RegExp(r'食物繊維');
final _saltLabel = RegExp(r'(食塩相当量|食塩)');

/// OCR 文字列を解析する
LabelValues parseLabelText(String raw) {
  final t = _halfwidth(raw);

  var kcal = _after(t, _kcalLabel);
  var p = _after(t, _protLabel);
  var f = _after(t, _fatLabel);
  var c = _after(t, _carbLabel);
  final salt = _after(t, _saltLabel);
  if (c == null) {
    final sugar = _after(t, _sugarLabel);
    final fiber = _after(t, _fiberLabel);
    if (sugar != null) c = sugar + (fiber ?? 0);
  }

  // 「250kcal」の形を優先（ラベルと値が別の列に読まれた場合）
  final kcalUnit = RegExp(r'(\d+(?:\.\d+)?)\s*kcal').firstMatch(t);
  if (kcalUnit != null) kcal = double.tryParse(kcalUnit.group(1)!);

  // ラベル列と値の列が分かれて読まれたとき：kcal の後ろの「数値 g」を順に P・F・C に割り当てる
  if (kcalUnit != null && (p == null || f == null || c == null)) {
    final grams = RegExp(r'(\d+(?:\.\d+)?)\s*g\b')
        .allMatches(t.substring(kcalUnit.end))
        .map((m) => double.tryParse(m.group(1)!))
        .whereType<double>()
        .toList();
    if (grams.length >= 3) {
      p ??= grams[0];
      f ??= grams[1];
      c ??= grams[2];
    }
  }

  // 表示単位
  String? unitLabel;
  double? unitGrams;
  bool? per100;
  final unit = RegExp(r'(1\s*(?:袋|個|本|食|枚|パック|カップ|杯|缶|切れ|包装|箱|人前))\s*[\(（]?\s*(\d+(?:\.\d+)?)?\s*(?:g|ml)?\s*[\)）]?\s*(?:当たり|あたり)')
      .firstMatch(t);
  if (unit != null) {
    unitLabel = unit.group(1)!.replaceAll(' ', '');
    unitGrams = unit.group(2) == null ? null : double.tryParse(unit.group(2)!);
    per100 = false;
  } else if (RegExp(r'100\s*(?:g|ml)\s*(?:当たり|あたり)').hasMatch(t)) {
    per100 = true;
  }

  return LabelValues(
    kcal: kcal,
    protein: p,
    fat: f,
    carbs: c,
    salt: salt,
    unitLabel: unitLabel,
    unitGrams: unitGrams,
    per100: per100,
  );
}

/// JAN（EAN-13 / EAN-8）のチェックディジット検証
bool isValidJan(String code) {
  if (!RegExp(r'^\d{8}$|^\d{13}$').hasMatch(code)) return false;
  final digits = code.split('').map(int.parse).toList();
  final check = digits.removeLast();
  var sum = 0;
  for (var i = 0; i < digits.length; i++) {
    // 右から数えて奇数桁（チェックディジットの左隣）が ×3
    final fromRight = digits.length - i;
    sum += digits[i] * (fromRight.isOdd ? 3 : 1);
  }
  return (10 - sum % 10) % 10 == check;
}

/// Haiku の転記結果（短いキーの JSON）を読む
({LabelValues values, String? jan}) parseLabelJson(String raw) {
  final text = raw.trim();
  Object? decoded = _tryJson(text);
  if (decoded is! Map) {
    final s = text.indexOf('{');
    final e = text.lastIndexOf('}');
    if (s >= 0 && e > s) decoded = _tryJson(text.substring(s, e + 1));
  }
  if (decoded is! Map) throw const FormatException('読み取り結果（JSON）を読めませんでした');
  double? n(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.replaceAll(RegExp(r'[^0-9.]'), ''));
  String? str(Object? v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty || s == 'null') ? null : s;
  }

  final jan = str(decoded['j'])?.replaceAll(RegExp(r'\D'), '');
  return (
    values: LabelValues(
      name: str(decoded['n']),
      kcal: n(decoded['e']),
      protein: n(decoded['p']),
      fat: n(decoded['f']),
      carbs: n(decoded['c']),
      salt: n(decoded['s']),
      unitLabel: str(decoded['u']),
      unitGrams: n(decoded['ug']),
      per100: decoded['p100'] == true,
    ),
    jan: (jan != null && isValidJan(jan)) ? jan : null,
  );
}

Object? _tryJson(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}
