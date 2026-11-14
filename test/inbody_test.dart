import 'package:flutter_test/flutter_test.dart';
import 'package:meal_log/core/inbody.dart';

/// InBody270 の結果用紙の QR と同じ形式の架空データ（実在の測定値ではない）
const sample =
    'https://qrcode.inbody.com?IBData=270-10000000021!!!!!!!!!!!!!!!!!!!!!!!!!!!!17500400M2026110107301501200100012204000360044001000800160004400380046506000700057307761039034010700840022901430780674-0026-0026!0000166600850080009000500800952600000000000000000000003000305002502400238026502700021021002080PASS00408003730097040303060646000002200150008511011000111220000000810270-2DM-0385!!!!10590548018502500300010002000340033002640980099000050005005200090009028103430800008600';

/// InBody470（本体画面の QR）と同じ形式の架空データ。位置が確定していない部分は 0 にしてある
const sample470 =
    'https://qrcode.inbody.com?IBData=470-10000000021!!!!!!!!!!!!!!!!!!!!!!!!!!!!17500400M2026010109000001200100012204000360044001000800160004400380046505600450055006000480059007000573077610390340107008400229014303400330026409800990000500050052000900090780674-0026-0026!000000000000000085008000900000000000000000000000000000300030500250240023802650270002102100208023002350019018501830PASS00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000470-2DM-0385!!!!0000000000000000000000000000000000000000000002810343080000000185025003000100020000';

void main() {
  group('InBody QR', () {
    test('基本項目', () {
      final r = parseInBodyQr(sample);
      expect(r.model, '270');
      expect(r.heightCm, 175.0);
      expect(r.age, 40);
      expect(r.sex, 'M');
      expect(r.measuredAt, DateTime(2026, 11, 1, 7, 30, 15));
      expect(r.weight.value, 70.0);
      expect(r.weight.low, closeTo(57.3, 1e-9));
      expect(r.weight.high, closeTo(77.6, 1e-9));
      expect(r.smm.value, 34.0);
      expect(r.smm.low, closeTo(28.1, 1e-9));
      expect(r.smm.high, closeTo(34.3, 1e-9));
      expect(r.bfm.value, 10.0);
      expect(r.pbf.value, closeTo(14.3, 1e-9));
      expect(r.pbf.low, 10.0);
      expect(r.pbf.high, 20.0);
      expect(r.bmi.value, closeTo(22.9, 1e-9));
      expect(r.bmi.low, 18.5);
      expect(r.bmi.high, 25.0);
      expect(r.score, 78);
    });

    test('体成分・調整・研究項目', () {
      final r = parseInBodyQr(sample);
      expect(r.tbw.value, 44.0);
      expect(r.protein.value, 12.0);
      expect(r.mineral.value, closeTo(4.0, 1e-9));
      expect(r.mineral.low, closeTo(3.6, 1e-9));
      expect(r.ffm, 60.0);
      expect(r.targetWeight, closeTo(67.4, 1e-9));
      expect(r.weightControl, closeTo(-2.6, 1e-9));
      expect(r.fatControl, closeTo(-2.6, 1e-9));
      expect(r.muscleControl, 0);
      expect(r.bmr, 1666);
      expect(r.whr.value, closeTo(0.85, 1e-9));
      expect(r.whr.low, closeTo(0.80, 1e-9));
      expect(r.whr.high, closeTo(0.90, 1e-9));
      expect(r.recommendedKcal, 2600);
      expect(r.waistCm, 80.0);
      expect(r.visceralLevel, 4);
      expect(r.weightPct, closeTo(103.9, 1e-9));
      expect(r.smmPct, closeTo(107.0, 1e-9));
      expect(r.bfmPct, closeTo(84.0, 1e-9));
    });

    test('部位別・インピーダンス', () {
      final r = parseInBodyQr(sample);
      expect(r.segmentLean.values, [3.4, 3.3, 26.4, 9.8, 9.9].map((v) => closeTo(v, 1e-9)).toList());
      expect(r.segmentFat.values, [0.5, 0.5, 5.2, 0.9, 0.9].map((v) => closeTo(v, 1e-9)).toList());
      expect(r.impedances.map((z) => z.label), ['20kHz', '100kHz']);
      expect(r.impedances[0].values.rightArm, closeTo(300.0, 1e-9));
      expect(r.impedances[0].values.trunk, closeTo(25.0, 1e-9));
      expect(r.impedances[1].values.leftLeg, closeTo(208.0, 1e-9));
    });

    test('InBody470', () {
      final r = parseInBodyQr(sample470);
      expect(r.model, '470');
      expect(r.heightCm, 175.0);
      expect(r.age, 40);
      expect(r.measuredAt, DateTime(2026, 1, 1, 9, 0, 0));
      expect(r.weight.value, 70.0);
      expect(r.weight.low, 57.3);
      expect(r.ffm, 60.0);
      expect(r.bfm.value, 10.0);
      expect(r.tbw.value, 44.0);
      expect(r.smm.value, 34.0);
      expect(r.smm.low, 28.1);
      expect(r.bmi.value, 22.9);
      expect(r.pbf.value, 14.3);
      expect(r.pbf.high, 20.0);
      expect(r.score, 78);
      expect(r.targetWeight, 67.4);
      expect(r.weightControl, closeTo(-2.6, 1e-9));
      expect(r.whr.value, 0.85);
      expect(r.waistCm, 80.0);
      expect(r.segmentLean.values, [3.4, 3.3, 26.4, 9.8, 9.9].map((v) => closeTo(v, 1e-9)).toList());
      expect(r.segmentFat.trunk, closeTo(5.2, 1e-9));
      expect(r.impedances.map((z) => z.label), ['5kHz', '50kHz', '500kHz']);
      expect(r.impedances[0].values.rightArm, closeTo(300.0, 1e-9));
      expect(r.impedances[2].values.leftLeg, closeTo(183.0, 1e-9));
      // 位置が確定していない項目は読まない
      expect(r.bmr, isNull);
      expect(r.recommendedKcal, isNull);
      expect(r.visceralLevel, isNull);
    });

    test('InBody470 も数値が合わなければ取り込まない', () {
      final broken = sample470.replaceFirst('070005730776', '080005730776');
      expect(() => parseInBodyQr(broken), throwsA(isA<InBodyFormatException>()));
    });

    test('IBData の値だけでも読める', () {
      final r = parseInBodyQr(sample.split('IBData=').last);
      expect(r.weight.value, 70.0);
    });

    test('標準範囲の判定', () {
      expect(const InBodyValue(5, 10, 20).level, -1);
      expect(const InBodyValue(15, 10, 20).level, 0);
      expect(const InBodyValue(25, 10, 20).level, 1);
      expect(const InBodyValue(25).level, isNull);
    });

    test('InBody 以外の QR は拒否', () {
      expect(() => parseInBodyQr('https://example.com/'), throwsA(isA<InBodyFormatException>()));
    });

    test('未対応機種は拒否', () {
      expect(() => parseInBodyQr(sample.replaceFirst('IBData=270', 'IBData=570')),
          throwsA(isA<InBodyFormatException>()));
    });

    test('数値が合わないときは取り込まない', () {
      // 体重だけを書き換えて整合性を崩す
      final broken = sample.replaceFirst('070005730776', '080005730776');
      expect(() => parseInBodyQr(broken), throwsA(isA<InBodyFormatException>()));
    });

    test('途中で切れたデータは拒否', () {
      expect(() => parseInBodyQr(sample.substring(0, 200)), throwsA(isA<InBodyFormatException>()));
    });
  });
}
