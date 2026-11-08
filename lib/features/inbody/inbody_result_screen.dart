import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/dates.dart';
import '../../core/inbody.dart';
import '../../data/entities.dart';
import '../../widgets/inbody_widgets.dart';
import '../../widgets/share_capture.dart';

/// InBody の結果表示。[record] が null のときは読み取り直後の確認画面（保存ボタンつき）
class InBodyResultScreen extends StatefulWidget {
  const InBodyResultScreen({super.key, required this.result, this.record});

  final InBodyResult result;
  final InBodyRecord? record;

  bool get isPreview => record == null;

  @override
  State<InBodyResultScreen> createState() => _InBodyResultScreenState();
}

class _InBodyResultScreenState extends State<InBodyResultScreen> {
  late DateTime _date;
  bool _reflectWeight = true;
  bool _setGoal = false;
  bool _saving = false;
  InBodyRecord? _previous;
  InBodyRecord? _alreadySaved;
  int? _currentGoalKcal;

  final _shareKey = GlobalKey();

  AppServices get s => AppServices.I;
  InBodyResult get r => widget.result;

  void _share() {
    final m = r.measuredAt;
    final text = [
      'InBody${m == null ? '' : '（${m.year}/${m.month}/${m.day}）'}',
      '体重 ${r.weight.value.toStringAsFixed(1)}kg',
      '骨格筋量 ${r.smm.value.toStringAsFixed(1)}kg',
      '体脂肪率 ${r.pbf.value.toStringAsFixed(1)}%',
      'InBody点数 ${r.score}点',
    ].join('・');
    shareCapture(context, _shareKey, text: text, fileName: 'inbody_result');
  }

  @override
  void initState() {
    super.initState();
    _date = widget.record != null ? parseYmd(widget.record!.date) : _defaultDate();
    _load();
  }

  /// 用紙の日付が直近3日以内ならその日、そうでなければ今日（本体の時計がずれていることがあるため）
  DateTime _defaultDate() {
    final today = dayOnly(DateTime.now());
    final m = r.measuredAt;
    if (m == null) return today;
    final d = dayOnly(m);
    if (d.isAfter(today) || d.isBefore(addDays(today, -3))) return today;
    return d;
  }

  bool get _sheetDateDiffers => r.measuredAt != null && ymd(r.measuredAt!) != ymd(_date);

  Future<void> _load() async {
    final all = await s.db.inbodyResults();
    final saved = widget.isPreview ? await s.db.findInBodyByRaw(r.raw) : null;
    final goal = await s.db.goalOn(ymd(DateTime.now()));
    if (!mounted) return;
    setState(() {
      _alreadySaved = saved;
      _currentGoalKcal = goal.targetKcal;
      _previous = _findPrevious(all);
    });
  }

  /// この結果より前の記録（新しい順の一覧から探す）
  InBodyRecord? _findPrevious(List<InBodyRecord> all) {
    final day = ymd(_date);
    for (final e in all) {
      if (e.raw == r.raw) continue;
      if (e.date.compareTo(day) < 0) return e;
      if (e.date == day && widget.record?.id != null && (e.id ?? 0) < widget.record!.id!) return e;
    }
    return null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: dayOnly(DateTime.now()),
    );
    if (picked == null) return;
    setState(() => _date = dayOnly(picked));
    _load();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final day = ymd(_date);
    try {
      await s.db.saveInBody(InBodyRecord(
        date: day,
        measuredAt: r.measuredAt,
        raw: r.raw,
        weightKg: r.weight.value,
        smmKg: r.smm.value,
        bfmKg: r.bfm.value,
        pbf: r.pbf.value,
        score: r.score,
        createdAt: DateTime.now(),
      ));
      if (_reflectWeight) {
        await s.db.saveWeight(WeightEntry(date: day, kg: r.weight.value));
      }
      if (_setGoal) {
        final today = ymd(DateTime.now());
        final g = await s.db.goalOn(today);
        await s.db.saveGoal(Goal(
          startDate: today,
          targetKcal: r.recommendedKcal,
          pRatio: g.pRatio,
          fRatio: g.fRatio,
          cRatio: g.cRatio,
        ));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('InBody の結果を保存しました')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存できませんでした：$e')));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('この InBody の結果を削除しますか？'),
        content: const Text('体重記録・目標カロリーは削除されません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('削除')),
        ],
      ),
    );
    if (ok != true || widget.record?.id == null) return;
    await s.db.deleteInBody(widget.record!.id!);
    if (mounted) Navigator.of(context).pop(true);
  }

  String _dateTimeText(DateTime d) =>
      '${d.year}/${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _range(InBodyValue v, int digits) =>
      (v.low == null || v.high == null) ? '' : '${v.low!.toStringAsFixed(digits)}〜${v.high!.toStringAsFixed(digits)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prev = _previous;
    final isMale = r.sex != 'F';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isPreview ? 'InBody 読み取り結果' : 'InBody ${jpDate(_date)}'),
        actions: [
          ShareButton(onPressed: _share),
          if (!widget.isPreview)
            IconButton(tooltip: '削除', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      bottomNavigationBar: widget.isPreview ? _saveBar(context) : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (widget.isPreview && _alreadySaved != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'この用紙は ${jpDate(parseYmd(_alreadySaved!.date))} の記録として保存済みです。保存すると上書きします。',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),

          ShareFrame(
            captureKey: _shareKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 見出し：点数と基本情報
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 84,
                          height: 84,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: theme.colorScheme.primary, width: 5),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${r.score}',
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                              Text('/100点', style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('InBody点数', style: theme.textTheme.titleSmall),
                              const SizedBox(height: 6),
                              Text('身長 ${r.heightCm.toStringAsFixed(1)} cm'
                                  '${r.age == null ? '' : '・${r.age}歳'}・${r.sexLabel}'),
                              if (r.measuredAt != null)
                                Text('測定 ${_dateTimeText(r.measuredAt!)}（InBody${r.model}）',
                                    style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 主要3項目
                Row(
                  children: [
                    Expanded(
                      child: InBodyStatTile(
                        label: '体重',
                        value: r.weight.value.toStringAsFixed(1),
                        unit: 'kg',
                        level: r.weight.level,
                        diff: prev == null ? null : r.weight.value - prev.weightKg,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InBodyStatTile(
                        label: '骨格筋量',
                        value: r.smm.value.toStringAsFixed(1),
                        unit: 'kg',
                        level: r.smm.level,
                        diff: prev == null ? null : r.smm.value - prev.smmKg,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InBodyStatTile(
                        label: '体脂肪率',
                        value: r.pbf.value.toStringAsFixed(1),
                        unit: '%',
                        level: r.pbf.level,
                        diff: prev == null ? null : r.pbf.value - prev.pbf,
                      ),
                    ),
                  ],
                ),
                if (prev != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('前回：${jpDate(parseYmd(prev.date))}',
                        textAlign: TextAlign.right, style: theme.textTheme.bodySmall),
                  ),
                const SizedBox(height: 12),

                InBodySection(
                  title: '体成分分析',
                  subtitle: 'Body Composition',
                  child: Column(
                    children: [
                      InBodyValueRow(
                          label: '体水分量', value: r.tbw.value.toStringAsFixed(1), unit: 'kg',
                          range: _range(r.tbw, 1), level: r.tbw.level),
                      InBodyValueRow(
                          label: 'タンパク質', value: r.protein.value.toStringAsFixed(1), unit: 'kg',
                          range: _range(r.protein, 1), level: r.protein.level),
                      InBodyValueRow(
                          label: 'ミネラル', value: r.mineral.value.toStringAsFixed(2), unit: 'kg',
                          range: _range(r.mineral, 2), level: r.mineral.level),
                      InBodyValueRow(
                          label: '体脂肪量', value: r.bfm.value.toStringAsFixed(1), unit: 'kg',
                          range: _range(r.bfm, 1), level: r.bfm.level),
                      const Divider(),
                      InBodyValueRow(label: '除脂肪量', value: r.ffm.toStringAsFixed(1), unit: 'kg'),
                      InBodyValueRow(
                          label: '体重', value: r.weight.value.toStringAsFixed(1), unit: 'kg',
                          range: _range(r.weight, 1), level: r.weight.level, bold: true),
                    ],
                  ),
                ),

                InBodySection(
                  title: '筋肉・脂肪分析',
                  subtitle: '標準＝100%',
                  child: Column(
                    children: [
                      InBodyRangeBar(
                        label: '体重',
                        valueText: '${r.weight.value.toStringAsFixed(1)}kg',
                        position: r.weightPct,
                        min: 55, max: 205, normalLow: 85, normalHigh: 115,
                        ticks: const [70, 100, 130, 160, 190],
                      ),
                      InBodyRangeBar(
                        label: '骨格筋量',
                        valueText: '${r.smm.value.toStringAsFixed(1)}kg',
                        position: r.smmPct,
                        min: 70, max: 170, normalLow: 90, normalHigh: 110,
                        ticks: const [80, 100, 120, 140, 160],
                      ),
                      InBodyRangeBar(
                        label: '体脂肪量',
                        valueText: '${r.bfm.value.toStringAsFixed(1)}kg',
                        position: r.bfmPct,
                        min: 40, max: 520, normalLow: 80, normalHigh: 160,
                        ticks: const [100, 220, 340, 460],
                      ),
                    ],
                  ),
                ),

                InBodySection(
                  title: '肥満分析',
                  child: Column(
                    children: [
                      InBodyRangeBar(
                        label: 'BMI',
                        valueText: r.bmi.value.toStringAsFixed(1),
                        position: r.bmi.value,
                        min: 10, max: 55,
                        normalLow: r.bmi.low ?? 18.5, normalHigh: r.bmi.high ?? 25,
                        ticks: const [15, 25, 35, 45],
                      ),
                      InBodyRangeBar(
                        label: '体脂肪率',
                        valueText: '${r.pbf.value.toStringAsFixed(1)}%',
                        position: r.pbf.value,
                        min: isMale ? 0 : 8, max: isMale ? 50 : 58,
                        normalLow: r.pbf.low ?? (isMale ? 10 : 18), normalHigh: r.pbf.high ?? (isMale ? 20 : 28),
                        ticks: isMale ? const [10, 20, 30, 40] : const [18, 28, 38, 48],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          InBodySection(
            title: '部位別筋肉量',
            child: InBodySegmentFigure(segments: r.segmentLean),
          ),

          InBodySection(
            title: '部位別体脂肪量',
            child: InBodySegmentFigure(segments: r.segmentFat, digits: const [1, 1, 1, 1, 1]),
          ),

          InBodySection(
            title: '体重調整',
            child: Column(
              children: [
                InBodyValueRow(label: '目標体重', value: r.targetWeight.toStringAsFixed(1), unit: 'kg', bold: true),
                InBodyValueRow(label: '体重調整', value: signed1(r.weightControl), unit: 'kg'),
                InBodyValueRow(label: '脂肪調整', value: signed1(r.fatControl), unit: 'kg'),
                InBodyValueRow(label: '筋肉調整', value: signed1(r.muscleControl), unit: 'kg'),
              ],
            ),
          ),

          InBodySection(
            title: '研究項目',
            child: Column(
              children: [
                if (r.visceralLevel != null) ...[
                  InBodyRangeBar(
                    label: '内臓脂肪',
                    valueText: 'Lv ${r.visceralLevel}',
                    position: r.visceralLevel!.toDouble(),
                    min: 0, max: 20, normalLow: 0, normalHigh: 9.5,
                    ticks: const [1, 10, 20],
                  ),
                  const SizedBox(height: 4),
                ],
                InBodyValueRow(label: '基礎代謝量', value: '${r.bmr}', unit: 'kcal'),
                InBodyValueRow(label: '推奨エネルギー摂取量', value: '${r.recommendedKcal}', unit: 'kcal'),
                InBodyValueRow(
                    label: 'ウエストヒップ比', value: r.whr.value.toStringAsFixed(2),
                    range: _range(r.whr, 2), level: r.whr.level),
                InBodyValueRow(label: '腹囲', value: r.waistCm.toStringAsFixed(1), unit: 'cm'),
              ],
            ),
          ),

          Card(
            margin: EdgeInsets.zero,
            child: ExpansionTile(
              title: const Text('インピーダンス'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [_impedanceTable(context)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _impedanceTable(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    TableRow row(String head, List<String> cells, {bool bold = false}) => TableRow(
          children: [head, ...cells]
              .map((t) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(t,
                        textAlign: TextAlign.right,
                        style: bold ? style?.copyWith(fontWeight: FontWeight.bold) : style),
                  ))
              .toList(),
        );
    String f(double v) => v.toStringAsFixed(1);
    return Table(
      columnWidths: const {0: FlexColumnWidth(1.3)},
      children: [
        row('Z(Ω)', ['右腕', '左腕', '体幹', '右脚', '左脚'], bold: true),
        row('20kHz', r.impedance20k.values.map(f).toList()),
        row('100kHz', r.impedance100k.values.map(f).toList()),
      ],
    );
  }

  Widget _saveBar(BuildContext context) {
    final theme = Theme.of(context);
    final goalText = _currentGoalKcal == null ? '' : '（今：$_currentGoalKcal kcal）';
    return SafeArea(
      child: Material(
        elevation: 8,
        color: theme.colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('記録日'),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: _pickDate, child: Text(jpDate(_date))),
                  const SizedBox(width: 8),
                  if (_sheetDateDiffers)
                    Expanded(
                      child: Text(
                        '用紙の日付 ${r.measuredAt!.year}/${r.measuredAt!.month}/${r.measuredAt!.day}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _reflectWeight,
                onChanged: (v) => setState(() => _reflectWeight = v ?? true),
                title: Text('体重記録にも反映（${r.weight.value.toStringAsFixed(1)} kg）'),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _setGoal,
                onChanged: (v) => setState(() => _setGoal = v ?? false),
                title: Text('目標カロリーを推奨摂取量 ${r.recommendedKcal}kcal にする$goalText'),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '保存中…' : '保存する'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
