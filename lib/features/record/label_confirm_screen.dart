import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/theme.dart';
import '../../core/food_db.dart';
import '../../core/format.dart';
import '../../core/label_text.dart';
import '../../core/portion.dart';
import '../../data/entities.dart';

/// 栄養成分表示の読み取り結果を確認して、登録食品（個人DB）に保存する。転記ミス対策として必ずこの画面を通す
class LabelConfirmScreen extends StatefulWidget {
  const LabelConfirmScreen({super.key, required this.values, this.jan, this.via});

  final LabelValues values;
  final String? jan;

  /// 読み取り方法（端末OCR / Haiku）
  final String? via;

  @override
  State<LabelConfirmScreen> createState() => _LabelConfirmScreenState();
}

class _LabelConfirmScreenState extends State<LabelConfirmScreen> {
  late final _name = TextEditingController(text: widget.values.name ?? '');
  late final _unit = TextEditingController(text: widget.values.unitLabel ?? '1食');
  late final _unitGrams = TextEditingController(text: _t(widget.values.unitGrams));
  late final _kcal = TextEditingController(text: _t(widget.values.kcal));
  late final _p = TextEditingController(text: _t(widget.values.protein));
  late final _f = TextEditingController(text: _t(widget.values.fat));
  late final _c = TextEditingController(text: _t(widget.values.carbs));
  late final _salt = TextEditingController(text: _t(widget.values.salt));
  late final _jan = TextEditingController(text: widget.jan ?? '');
  late bool _per100 = widget.values.per100 ?? false;
  bool _save = true;
  bool _busy = false;

  static String _t(double? v) => v == null ? '' : fmtNum(v);

  @override
  void dispose() {
    for (final c in [_name, _unit, _unitGrams, _kcal, _p, _f, _c, _salt, _jan]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _n(TextEditingController c) => double.tryParse(c.text.trim());

  bool get _consistent {
    final k = _n(_kcal), p = _n(_p), f = _n(_f), c = _n(_c);
    if (k == null || p == null || f == null || c == null) return false;
    return atwaterOk(k, p, f, c);
  }

  Future<void> _ok() async {
    final kcal = _n(_kcal);
    if (kcal == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('エネルギー（kcal）を入力してください')));
      return;
    }
    final jan = _jan.text.trim();
    final food = UserFood(
      name: _name.text.trim().isEmpty ? '市販品' : _name.text.trim(),
      jan: jan.isEmpty ? null : jan,
      kcal: kcal,
      protein: _n(_p),
      fat: _n(_f),
      carbs: _n(_c),
      salt: _n(_salt),
      unitLabel: _per100 ? '100g' : (_unit.text.trim().isEmpty ? '1食' : _unit.text.trim()),
      grams: _n(_unitGrams),
      per100g: _per100,
    );
    setState(() => _busy = true);
    FoodRecord rec;
    if (_save) {
      rec = await AppServices.I.foods.saveUserFood(food);
    } else {
      rec = FoodRecord(
        ref: 'label:${DateTime.now().millisecondsSinceEpoch}',
        source: FoodSource.personal,
        name: food.name,
        kcal: food.kcal,
        protein: food.protein,
        fat: food.fat,
        carbs: food.carbs,
        salt: food.salt,
        per100g: food.per100g,
        servingGrams: food.grams,
        servingLabel: food.unitLabel,
      );
    }
    if (mounted) Navigator.of(context).pop(rec);
  }

  Widget _num(TextEditingController c, String label, {String? suffix}) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: suffix, isDense: true, border: const OutlineInputBorder()),
        onChanged: (_) => setState(() {}),
      );

  @override
  Widget build(BuildContext context) {
    final janText = _jan.text.trim();
    final janBad = janText.isNotEmpty && !isValidJan(janText);
    return Scaffold(
      appBar: AppBar(title: const Text('栄養成分表示の確認')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _busy ? null : _ok,
            icon: const Icon(Icons.check),
            label: const Text('この内容で使う'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.via != null) Text('読み取り：${widget.via}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Card(
            color: _consistent ? null : AppColors.warning.withAlpha(40),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_consistent
                  ? 'パッケージの表示と同じか確認してください（kcal と P・F・C の整合性はOK）'
                  : 'kcal と P×4＋F×9＋C×4 が合いません。パッケージの数値と見比べて直してください'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: '商品名', isDense: true, border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _per100,
            onChanged: (v) => setState(() => _per100 = v),
            title: const Text('100g（100ml）当たりの表示'),
            subtitle: const Text('オンなら記録時に食べたグラム数を入れます'),
          ),
          Row(
            children: [
              if (!_per100) ...[
                Expanded(
                  child: TextField(
                    controller: _unit,
                    decoration: const InputDecoration(labelText: '表示単位', hintText: '1袋', isDense: true, border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(child: _num(_unitGrams, _per100 ? '内容量' : '表示単位の重さ', suffix: 'g')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _num(_kcal, 'エネルギー', suffix: 'kcal')),
              const SizedBox(width: 8),
              Expanded(child: _num(_salt, '食塩相当量', suffix: 'g')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _num(_p, 'たんぱく質', suffix: 'g')),
              const SizedBox(width: 8),
              Expanded(child: _num(_f, '脂質', suffix: 'g')),
              const SizedBox(width: 8),
              Expanded(child: _num(_c, '炭水化物', suffix: 'g')),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _jan,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'JANコード（任意）',
              errorText: janBad ? 'JANの形式（8桁・13桁）が正しくありません' : null,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _save,
            onChanged: (v) => setState(() => _save = v ?? true),
            title: const Text('登録食品に保存する'),
            subtitle: const Text('次回から検索・バーコードで撮影なしに呼び出せます'),
          ),
        ],
      ),
    );
  }
}
