/// InBody の結果用紙に印字される QR コード（`https://qrcode.inbody.com?IBData=...`）の解析。
///
/// IBData は数字を固定桁で並べた平文。桁位置は公開されていないため、
/// InBody270 の実物の結果用紙（2026-11）と照合して決めた。
/// - 照合済み：研究項目・インピーダンス・体成分（体水分量＋タンパク質＋ミネラル＝除脂肪量、
///   除脂肪量＋体脂肪量＝体重、BMI＝体重÷身長²が成り立つことを確認）
/// - 推定：年齢・内臓脂肪レベル（1サンプルのみで確認）
/// InBody470（2026-11-14、本体画面の QR 1件）は並びが違う。体成分・部位別・点数・調整・
/// インピーダンス（5/50/500kHz）は 270 と同じ形の値が並ぶ位置で確認し、上の整合性も成り立つ。
/// 基礎代謝量・推奨摂取量・内臓脂肪レベルは位置が確定できないため読まない（null）。
/// 位置がずれた場合に誤った値を保存しないよう、[parseInBodyQr] は上記の整合性を検査する。
library;

/// 範囲つきの測定値（範囲は InBody が示す標準範囲）
class InBodyValue {
  const InBodyValue(this.value, [this.low, this.high]);

  final double value;
  final double? low;
  final double? high;

  /// 標準範囲に対する位置：-1 低い / 0 標準 / 1 高い / null 範囲なし
  int? get level {
    if (low == null || high == null) return null;
    if (value < low!) return -1;
    if (value > high!) return 1;
    return 0;
  }
}

/// 部位別（右腕・左腕・体幹・右脚・左脚）
class InBodySegments {
  const InBodySegments(this.rightArm, this.leftArm, this.trunk, this.rightLeg, this.leftLeg);

  final double rightArm;
  final double leftArm;
  final double trunk;
  final double rightLeg;
  final double leftLeg;

  List<double> get values => [rightArm, leftArm, trunk, rightLeg, leftLeg];
}

class InBodyResult {
  const InBodyResult({
    required this.raw,
    required this.model,
    required this.heightCm,
    required this.age,
    required this.sex,
    required this.measuredAt,
    required this.weight,
    required this.smm,
    required this.bfm,
    required this.tbw,
    required this.protein,
    required this.mineral,
    required this.ffm,
    required this.bmi,
    required this.pbf,
    required this.weightPct,
    required this.smmPct,
    required this.bfmPct,
    required this.score,
    required this.targetWeight,
    required this.weightControl,
    required this.fatControl,
    required this.muscleControl,
    required this.bmr,
    required this.whr,
    required this.visceralLevel,
    required this.recommendedKcal,
    required this.waistCm,
    required this.segmentLean,
    required this.segmentFat,
    required this.impedances,
  });

  /// QR の文字列全体
  final String raw;

  /// 機種（例 "270"）
  final String model;
  final double heightCm;
  final int? age;

  /// 'M' / 'F'
  final String sex;

  /// 用紙の測定日時（InBody 本体の時計。ずれていることがある）
  final DateTime? measuredAt;

  final InBodyValue weight;

  /// 骨格筋量
  final InBodyValue smm;

  /// 体脂肪量
  final InBodyValue bfm;

  /// 体水分量
  final InBodyValue tbw;
  final InBodyValue protein;
  final InBodyValue mineral;

  /// 除脂肪量
  final double ffm;
  final InBodyValue bmi;

  /// 体脂肪率
  final InBodyValue pbf;

  /// 筋肉・脂肪グラフ用：標準値に対する %（100 = 標準）
  final double weightPct;
  final double smmPct;
  final double bfmPct;

  /// InBody 点数
  final int score;

  /// 目標体重・体重調整・脂肪調整・筋肉調整（kg）
  final double targetWeight;
  final double weightControl;
  final double fatControl;
  final double muscleControl;

  /// 基礎代謝量（kcal）。読めない機種は null
  final int? bmr;

  /// ウエストヒップ比
  final InBodyValue whr;
  final int? visceralLevel;

  /// 推奨エネルギー摂取量（kcal）。読めない機種は null
  final int? recommendedKcal;

  /// 腹囲（cm）
  final double waistCm;

  /// 部位別筋肉量（kg）
  final InBodySegments segmentLean;

  /// 部位別体脂肪量（kg）
  final InBodySegments segmentFat;

  /// インピーダンス（Ω）。周波数の表示名と部位別の値（270 は 20/100kHz、470 は 5/50/500kHz）
  final List<({String label, InBodySegments values})> impedances;

  String get sexLabel => sex == 'F' ? '女性' : '男性';
}

/// 読み取った文字列が InBody の QR でない・解析できないとき
class InBodyFormatException implements Exception {
  const InBodyFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// QR の文字列（URL 全体でも IBData の値だけでもよい）から IBData を取り出す
String? extractIbData(String text) {
  final t = text.trim();
  final i = t.indexOf('IBData=');
  if (i >= 0) {
    var v = t.substring(i + 'IBData='.length);
    final amp = v.indexOf('&');
    if (amp >= 0) v = v.substring(0, amp);
    return Uri.decodeQueryComponent(v.replaceAll('+', '%2B'));
  }
  if (RegExp(r'^\d{3}-').hasMatch(t)) return t;
  return null;
}

class _Reader {
  _Reader(this.d);

  final String d;

  String str(int at, int len) {
    if (at + len > d.length) throw const InBodyFormatException('データが途中で切れています');
    return d.substring(at, at + len);
  }

  int integer(int at, int len) {
    final s = str(at, len);
    final v = int.tryParse(s);
    if (v == null) throw InBodyFormatException('数値でない値があります（位置 $at: "$s"）');
    return v;
  }

  double dec(int at, int len, int scale) => integer(at, len) / scale;

  /// 先頭1文字が符号（+ / - / それ以外は正）
  double signed(int at, int len, int scale) {
    final sign = str(at, 1) == '-' ? -1 : 1;
    return sign * dec(at + 1, len - 1, scale);
  }

  /// 4桁×3（値・下限・上限）
  InBodyValue ranged(int at, int scale) =>
      InBodyValue(dec(at, 4, scale), dec(at + 4, 4, scale), dec(at + 8, 4, scale));

  /// 4桁×5（右腕・左腕・体幹・右脚・左脚）
  InBodySegments segments(int at, List<int> scales) => InBodySegments(
        dec(at, 4, scales[0]),
        dec(at + 4, 4, scales[1]),
        dec(at + 8, 4, scales[2]),
        dec(at + 12, 4, scales[3]),
        dec(at + 16, 4, scales[4]),
      );
}

DateTime? _parseDateTime(String s) {
  if (!RegExp(r'^\d{14}$').hasMatch(s)) return null;
  final y = int.parse(s.substring(0, 4));
  final mo = int.parse(s.substring(4, 6));
  final d = int.parse(s.substring(6, 8));
  final h = int.parse(s.substring(8, 10));
  final mi = int.parse(s.substring(10, 12));
  final se = int.parse(s.substring(12, 14));
  if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59 || se > 59) return null;
  return DateTime(y, mo, d, h, mi, se);
}

bool _near(double a, double b, [double tol = 0.35]) => (a - b).abs() <= tol;

/// InBody の QR を解析する。対応機種は InBody270・InBody470。
/// 解析できない・数値の整合性が取れないときは [InBodyFormatException]。
InBodyResult parseInBodyQr(String text) {
  final d = extractIbData(text);
  if (d == null) {
    throw const InBodyFormatException('InBody の結果用紙の QR コードではないようです');
  }
  final model = d.split('-').first;
  final InBodyResult result;
  switch (model) {
    case '270':
      result = _parse270(text, d);
    case '470':
      result = _parse470(text, d);
    default:
      throw InBodyFormatException('InBody$model の用紙にはまだ対応していません（対応：InBody270・470）');
  }
  _validate(result);
  return result;
}

InBodyResult _parse470(String text, String d) {
  final r = _Reader(d);
  final age = r.integer(47, 3);
  // 後半は "PASS" と "!!!!" の後ろからの位置で読む
  final pass = d.indexOf('PASS');
  final tail = d.indexOf('!!!!', pass < 0 ? 0 : pass);
  if (pass < 0 || tail < 0) throw const InBodyFormatException('InBody470 の QR の形式が想定と違います');
  final b = tail + 4;
  final imp = pass - 60;
  return InBodyResult(
    raw: text.trim(),
    model: '470',
    heightCm: r.dec(43, 4, 10),
    age: (age >= 3 && age <= 120) ? age : null,
    sex: r.str(51, 1) == 'F' ? 'F' : 'M',
    measuredAt: _parseDateTime(r.str(52, 14)),
    protein: r.ranged(66, 10),
    mineral: r.ranged(78, 100),
    bfm: r.ranged(90, 10),
    tbw: r.ranged(102, 10),
    // 114 は筋肉量（範囲つき）
    ffm: r.dec(126, 4, 10),
    weight: r.ranged(138, 10),
    weightPct: r.dec(150, 4, 10),
    smm: InBodyValue(r.dec(154, 4, 10), r.dec(b + 44, 4, 10), r.dec(b + 48, 4, 10)),
    smmPct: r.dec(158, 4, 10),
    bfmPct: r.dec(162, 4, 10),
    bmi: InBodyValue(r.dec(166, 4, 10), r.dec(b + 60, 4, 10), r.dec(b + 64, 4, 10)),
    pbf: InBodyValue(r.dec(170, 4, 10), r.dec(b + 72, 4, 10), r.dec(b + 76, 4, 10)),
    segmentLean: r.segments(174, const [100, 100, 10, 100, 100]),
    segmentFat: r.segments(194, const [10, 10, 10, 10, 10]),
    score: r.integer(214, 3),
    targetWeight: r.dec(217, 4, 10),
    weightControl: r.signed(221, 5, 10),
    fatControl: r.signed(226, 5, 10),
    muscleControl: r.signed(231, 5, 10),
    bmr: null,
    whr: r.ranged(246, 100),
    recommendedKcal: null,
    visceralLevel: null,
    waistCm: r.dec(b + 52, 4, 10),
    impedances: [
      (label: '5kHz', values: r.segments(imp, const [10, 10, 10, 10, 10])),
      (label: '50kHz', values: r.segments(imp + 20, const [10, 10, 10, 10, 10])),
      (label: '500kHz', values: r.segments(imp + 40, const [10, 10, 10, 10, 10])),
    ],
  );
}

InBodyResult _parse270(String text, String d) {
  const model = '270';
  final r = _Reader(d);

  final bmiRange = [r.dec(359, 4, 10), r.dec(363, 4, 10)];
  final pbfRange = [r.dec(371, 4, 10), r.dec(375, 4, 10)];
  final smmRange = [r.dec(419, 4, 10), r.dec(423, 4, 10)];
  final visceral = r.integer(270, 4) ~/ 10;
  final age = r.integer(47, 3);

  return InBodyResult(
    raw: text.trim(),
    model: model,
    heightCm: r.dec(43, 4, 10),
    age: (age >= 3 && age <= 120) ? age : null,
    sex: r.str(51, 1) == 'F' ? 'F' : 'M',
    measuredAt: _parseDateTime(r.str(52, 14)),
    protein: r.ranged(66, 10),
    mineral: r.ranged(78, 100),
    bfm: r.ranged(90, 10),
    tbw: r.ranged(102, 10),
    ffm: r.dec(114, 4, 10),
    weight: r.ranged(118, 10),
    weightPct: r.dec(130, 4, 10),
    smm: InBodyValue(r.dec(134, 4, 10), smmRange[0], smmRange[1]),
    smmPct: r.dec(138, 4, 10),
    bfmPct: r.dec(142, 4, 10),
    bmi: InBodyValue(r.dec(146, 4, 10), bmiRange[0], bmiRange[1]),
    pbf: InBodyValue(r.dec(150, 4, 10), pbfRange[0], pbfRange[1]),
    score: r.integer(154, 3),
    targetWeight: r.dec(157, 4, 10),
    weightControl: r.signed(161, 5, 10),
    fatControl: r.signed(166, 5, 10),
    muscleControl: r.signed(171, 5, 10),
    bmr: r.integer(176, 4),
    whr: r.ranged(180, 100),
    recommendedKcal: r.integer(202, 4),
    impedances: [
      (label: '20kHz', values: r.segments(226, const [10, 10, 10, 10, 10])),
      (label: '100kHz', values: r.segments(246, const [10, 10, 10, 10, 10])),
    ],
    visceralLevel: (visceral >= 1 && visceral <= 30) ? visceral : null,
    segmentLean: r.segments(379, const [100, 100, 10, 100, 100]),
    segmentFat: r.segments(399, const [10, 10, 10, 10, 10]),
    waistCm: r.dec(427, 4, 10),
  );
}

void _validate(InBodyResult x) {
  final w = x.weight.value;
  final ok = w >= 10 &&
      w <= 300 &&
      x.heightCm >= 80 &&
      x.heightCm <= 250 &&
      _near(x.ffm + x.bfm.value, w) &&
      _near(x.tbw.value + x.protein.value + x.mineral.value, x.ffm) &&
      _near(w / ((x.heightCm / 100) * (x.heightCm / 100)), x.bmi.value, 0.15) &&
      _near(x.weight.value + x.weightControl, x.targetWeight, 0.15);
  if (!ok) {
    throw const InBodyFormatException(
        '数値の組み合わせが合わないため取り込みを中止しました。用紙の形式が想定と違う可能性があります');
  }
}
