import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/format.dart';
import '../../core/links.dart';
import '../../core/meal_type.dart';
import '../../core/nutrition.dart';
import '../../data/entities.dart';
import '../../services/image_service.dart';
import '../../widgets/macro_widgets.dart';

/// 解析結果の確認・編集（新規記録と既存記録の編集で共用）
class ResultEditScreen extends StatefulWidget {
  const ResultEditScreen({
    super.key,
    required this.date,
    required this.mealType,
    required this.items,
    this.photoBytes,
    this.photoPath,
    this.modelUsed,
    this.note,
    this.hint,
    this.mealId,
    this.createdAt,
  });

  ResultEditScreen.edit({super.key, required Meal meal})
      : date = meal.date,
        mealType = meal.type,
        items = meal.items,
        photoBytes = null,
        photoPath = meal.photoPath,
        modelUsed = meal.modelUsed,
        note = meal.note,
        hint = null,
        mealId = meal.id,
        createdAt = meal.createdAt;

  final String date;
  final MealType mealType;
  final List<MealItem> items;
  final Uint8List? photoBytes;
  final String? photoPath;
  final String? modelUsed;
  final String? note;
  final String? hint;
  final int? mealId;
  final DateTime? createdAt;

  @override
  State<ResultEditScreen> createState() => _ResultEditScreenState();
}

class _ResultEditScreenState extends State<ResultEditScreen> {
  late MealType _type = widget.mealType;
  late String? _model = widget.modelUsed;
  late String? _note = widget.note;
  final _rows = <_ItemRow>[];
  bool _busy = false;

  AppServices get s => AppServices.I;

  @override
  void initState() {
    super.initState();
    _setRows(widget.items);
  }

  void _setRows(List<MealItem> items) {
    _disposeLater(List.of(_rows));
    _rows
      ..clear()
      ..addAll(items.map(_ItemRow.new));
  }

  /// 表示中の TextField が外れてから破棄する
  void _disposeLater(List<_ItemRow> rows) {
    if (rows.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final r in rows) {
        r.dispose();
      }
    });
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  bool get _hasPhoto => widget.photoBytes != null || widget.photoPath != null;

  Future<Uint8List?> _photoBytes() async {
    if (widget.photoBytes != null) return widget.photoBytes;
    final path = widget.photoPath;
    if (path == null) return null;
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> _reanalyze() async {
    final bytes = await _photoBytes();
    if (bytes == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sonnetで再解析'),
        content: const Text('より高精度なモデルで解析し直します（1回あたり約1〜2円）。今の入力内容は置き換わります。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('再解析')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final r = await s.nutrition.analyzePhoto(bytes, hint: widget.hint, reanalyze: true);
      if (!mounted) return;
      setState(() {
        _setRows(r.items.isEmpty ? [MealItem.manual] : r.items);
        _model = r.model;
        _note = r.note;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('再解析に失敗しました: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final items = _rows.map((r) => r.value).where((i) => i.name.isNotEmpty).toList();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('料理名を1つ以上入力してください')));
      return;
    }
    setState(() => _busy = true);
    try {
      var path = widget.photoPath;
      if (widget.photoBytes != null) path = await ImageService.saveThumb(widget.photoBytes!);
      await s.db.saveMeal(Meal(
        id: widget.mealId,
        date: widget.date,
        type: _type,
        createdAt: widget.createdAt ?? DateTime.now(),
        photoPath: path,
        modelUsed: _model,
        note: _note,
        items: items,
      ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存できませんでした: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = Pfc.sum(_rows.map((r) => r.value));
    return Scaffold(
      appBar: AppBar(title: Text(widget.mealId == null ? '内容を確認して記録' : '記録を編集')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            children: [
              if (widget.photoBytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(widget.photoBytes!, height: 200, fit: BoxFit.cover),
                )
              else if (widget.photoPath != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(widget.photoPath!),
                      height: 200, fit: BoxFit.cover, errorBuilder: (context, error, stack) => const SizedBox.shrink()),
                ),
              const SizedBox(height: 12),
              SegmentedButton<MealType>(
                segments: [for (final t in MealType.values) ButtonSegment(value: t, label: Text(t.label))],
                selected: {_type},
                onSelectionChanged: (sel) => setState(() => _type = sel.first),
              ),
              if (_note != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_note!)),
                      ],
                    ),
                  ),
                ),
              ],
              if (_model != null && _model != 'manual')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('解析：$_model', style: Theme.of(context).textTheme.bodySmall),
                ),
              const SizedBox(height: 8),
              for (var i = 0; i < _rows.length; i++)
                _ItemCard(
                  key: ObjectKey(_rows[i]),
                  row: _rows[i],
                  onChanged: () => setState(() {}),
                  onDelete: _rows.length <= 1
                      ? null
                      : () => setState(() {
                            _disposeLater([_rows.removeAt(i)]);
                          }),
                ),
              TextButton.icon(
                onPressed: () => setState(() => _rows.add(_ItemRow(MealItem.manual))),
                icon: const Icon(Icons.add),
                label: const Text('料理を追加'),
              ),
            ],
          ),
          if (_busy) ...[
            const ModalBarrier(dismissible: false, color: Colors.black38),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '合計 ${kcal0(total.kcal)} kcal   P ${g1(total.p)}g  F ${g1(total.f)}g  C ${g1(total.c)}g',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_hasPhoto) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _reanalyze,
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Sonnetで再解析'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.check),
                      label: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 1品分の入力欄。量を変えると base に対する比で kcal・PFC を自動計算する
class _ItemRow {
  _ItemRow(MealItem item)
      : base = item,
        name = TextEditingController(text: item.name),
        amount = TextEditingController(text: fmtNum(item.amount)),
        unit = TextEditingController(text: item.unit),
        grams = TextEditingController(text: item.grams == null ? '' : fmtNum(item.grams!)),
        kcal = TextEditingController(text: kcal0(item.kcal)),
        p = TextEditingController(text: g1(item.protein)),
        f = TextEditingController(text: g1(item.fat)),
        c = TextEditingController(text: g1(item.carbs));

  MealItem base;
  final TextEditingController name, amount, unit, grams, kcal, p, f, c;

  static double _num(String s, double fallback) => double.tryParse(s.trim()) ?? fallback;

  MealItem get value {
    final gText = grams.text.trim();
    return MealItem(
      name: name.text.trim(),
      amount: _num(amount.text, base.amount),
      unit: unit.text.trim().isEmpty ? '人前' : unit.text.trim(),
      grams: gText.isEmpty ? null : double.tryParse(gText),
      kcal: _num(kcal.text, 0),
      protein: _num(p.text, 0),
      fat: _num(f.text, 0),
      carbs: _num(c.text, 0),
      confidence: base.confidence,
      sourceType: base.sourceType,
      sourceUrl: base.sourceUrl,
    );
  }

  void _applyScaled(MealItem s, {required bool fromGrams}) {
    if (fromGrams) {
      amount.text = fmtNum(double.parse(s.amount.toStringAsFixed(2)));
    } else if (s.grams != null) {
      grams.text = fmtNum(double.parse(s.grams!.toStringAsFixed(1)));
    }
    kcal.text = kcal0(s.kcal);
    p.text = g1(s.protein);
    f.text = g1(s.fat);
    c.text = g1(s.carbs);
  }

  void onAmountChanged(String v) {
    final n = double.tryParse(v.trim());
    if (n == null || base.amount <= 0) return;
    _applyScaled(base.scaled(n / base.amount), fromGrams: false);
  }

  void onGramsChanged(String v) {
    final n = double.tryParse(v.trim());
    final g = base.grams;
    if (n == null || g == null || g <= 0) return;
    _applyScaled(base.scaled(n / g), fromGrams: true);
  }

  /// kcal・PFC を直接編集したら、それを新しい基準にする
  void onNutrientEdited() => base = value;

  void dispose() {
    for (final t in [name, amount, unit, grams, kcal, p, f, c]) {
      t.dispose();
    }
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({super.key, required this.row, required this.onChanged, this.onDelete});

  final _ItemRow row;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;

  Widget _field(TextEditingController c, String label, void Function(String) changed, {String? suffix}) =>
      TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (v) {
          changed(v);
          onChanged();
        },
      );

  @override
  Widget build(BuildContext context) {
    final b = row.base;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: row.name,
                    decoration: const InputDecoration(labelText: '料理名', isDense: true, border: OutlineInputBorder()),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                if (onDelete != null) IconButton(icon: const Icon(Icons.close), onPressed: onDelete),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _field(row.amount, '量', row.onAmountChanged)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: row.unit,
                    decoration: const InputDecoration(labelText: '単位', isDense: true, border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: _field(row.grams, '重さ', row.onGramsChanged, suffix: 'g')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _field(row.kcal, 'kcal', (_) => row.onNutrientEdited())),
                const SizedBox(width: 6),
                Expanded(child: _field(row.p, 'P', (_) => row.onNutrientEdited())),
                const SizedBox(width: 6),
                Expanded(child: _field(row.f, 'F', (_) => row.onNutrientEdited())),
                const SizedBox(width: 6),
                Expanded(child: _field(row.c, 'C', (_) => row.onNutrientEdited())),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                InfoChip(sourceLabel(b.sourceType)),
                if (b.sourceType != 'manual')
                  InfoChip(
                    confidenceLabel(b.confidence),
                    color: b.confidence == 'low' ? Theme.of(context).colorScheme.error : null,
                  ),
                if (b.sourceUrl != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => openUrl(b.sourceUrl!),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('出典'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
