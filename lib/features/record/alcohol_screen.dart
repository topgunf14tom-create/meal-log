import 'package:flutter/material.dart';

import '../../core/alcohol.dart';
import '../../data/entities.dart';

class _CartEntry {
  _CartEntry(this.drink, this.size, this.count);

  final Drink drink;
  final DrinkSize size;
  final double count;

  double get ml => size.ml * count;
  MealItem get item => drink.toItem(size, count);
}

String _countText(double c) => c == c.roundToDouble() ? c.toInt().toString() : c.toStringAsFixed(1);

IconData _iconFor(Drink d) {
  final n = d.name;
  if (n.contains('ビール') || n.contains('発泡酒')) return Icons.sports_bar;
  if (n.contains('ワイン')) return Icons.wine_bar;
  if (n.contains('日本酒') || n.contains('焼酎') || n.contains('梅酒')) return Icons.liquor;
  return Icons.local_bar;
}

/// お酒を選んで記録する。選んだ内容を [MealItem] の一覧で返す
class AlcoholScreen extends StatefulWidget {
  const AlcoholScreen({super.key});

  @override
  State<AlcoholScreen> createState() => _AlcoholScreenState();
}

class _AlcoholScreenState extends State<AlcoholScreen> {
  final _cart = <_CartEntry>[];

  double get _totalKcal => _cart.fold(0.0, (a, e) => a + e.item.kcal);
  double get _totalAlcohol => _cart.fold(0.0, (a, e) => a + e.drink.alcoholG(e.ml));

  Future<void> _pick(Drink drink) async {
    final entry = await showModalBottomSheet<_CartEntry>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DrinkSheet(drink: drink),
    );
    if (entry != null) setState(() => _cart.add(entry));
  }

  Future<void> _custom() async {
    final entry = await showDialog<_CartEntry>(context: context, builder: (_) => const _CustomDrinkDialog());
    if (entry != null) setState(() => _cart.add(entry));
  }

  void _done() => Navigator.of(context).pop(_cart.map((e) => e.item).toList());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('お酒を記録')),
      bottomNavigationBar: _cart.isEmpty ? null : _cartBar(context),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
        children: [
          for (final d in drinks)
            ListTile(
              leading: Icon(_iconFor(d)),
              title: Text(d.name),
              subtitle: Text(
                '${_countText(d.abv)}%・${d.sizes.first.label} 約${d.kcal(d.sizes.first.ml).round()}kcal',
              ),
              trailing: const Icon(Icons.add_circle_outline),
              onTap: () => _pick(d),
            ),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: const Text('その他のお酒'),
            subtitle: const Text('度数と量を入力'),
            trailing: const Icon(Icons.add_circle_outline),
            onTap: _custom,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'カロリーは「純アルコール量×7kcal＋糖質×4kcal」の目安です。商品によって差があります。',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartBar(BuildContext context) {
    final theme = Theme.of(context);
    final over = _totalAlcohol > dailyAlcoholGuideG;
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
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < _cart.length; i++)
                    InputChip(
                      label: Text('${_cart[i].drink.name} ${_cart[i].size.label}×${_countText(_cart[i].count)}'),
                      onDeleted: () => setState(() => _cart.removeAt(i)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('合計 ${_totalKcal.round()} kcal',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '純アルコール ${_totalAlcohol.toStringAsFixed(0)}g'
                      '（目安 ${dailyAlcoholGuideG.toInt()}g/日）',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: over ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: _done, child: const Text('内容を確認して記録')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// サイズと杯数を選ぶシート
class _DrinkSheet extends StatefulWidget {
  const _DrinkSheet({required this.drink});

  final Drink drink;

  @override
  State<_DrinkSheet> createState() => _DrinkSheetState();
}

class _DrinkSheetState extends State<_DrinkSheet> {
  late DrinkSize _size = widget.drink.sizes.first;
  double _count = 1;

  @override
  Widget build(BuildContext context) {
    final d = widget.drink;
    final theme = Theme.of(context);
    final ml = _size.ml * _count;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(d.name, style: theme.textTheme.titleLarge),
            if (d.note != null)
              Text(d.note!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final s in d.sizes)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: s == _size,
                    onSelected: (_) => setState(() => _size = s),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton.outlined(
                  onPressed: _count > 0.5 ? () => setState(() => _count -= 0.5) : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 72,
                  child: Text('${_countText(_count)} ${_size.unit}',
                      textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                ),
                IconButton.outlined(
                  onPressed: _count < 30 ? () => setState(() => _count += 0.5) : null,
                  icon: const Icon(Icons.add),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${d.kcal(ml).round()} kcal',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    Text('純アルコール ${d.alcoholG(ml).toStringAsFixed(1)}g', style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _CartEntry(d, _size, _count)),
                child: const Text('追加'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 度数と量を自分で入れる
class _CustomDrinkDialog extends StatefulWidget {
  const _CustomDrinkDialog();

  @override
  State<_CustomDrinkDialog> createState() => _CustomDrinkDialogState();
}

class _CustomDrinkDialogState extends State<_CustomDrinkDialog> {
  final _name = TextEditingController();
  final _abv = TextEditingController();
  final _ml = TextEditingController();
  final _carbs = TextEditingController(text: '0');

  @override
  void dispose() {
    _name.dispose();
    _abv.dispose();
    _ml.dispose();
    _carbs.dispose();
    super.dispose();
  }

  double? get _abvValue => double.tryParse(_abv.text.trim());
  double? get _mlValue => double.tryParse(_ml.text.trim());
  double get _carbsValue => double.tryParse(_carbs.text.trim()) ?? 0;

  bool get _valid {
    final a = _abvValue, m = _mlValue;
    return a != null && a >= 0 && a <= 100 && m != null && m > 0 && m <= 5000;
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label, {String? hint, String? suffix, bool number = true}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            controller: c,
            keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
            decoration: InputDecoration(labelText: label, hintText: hint, suffixText: suffix),
            onChanged: (_) => setState(() {}),
          ),
        );
    final preview = _valid ? customDrink(_name.text, _abvValue!, _carbsValue).kcal(_mlValue!).round() : null;
    return AlertDialog(
      title: const Text('その他のお酒'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            field(_name, '名前', hint: '例：マッコリ', number: false),
            field(_abv, '度数', hint: '例：6', suffix: '%'),
            field(_ml, '量', hint: '例：300', suffix: 'ml'),
            field(_carbs, '糖質（100mlあたり・分かれば）', suffix: 'g'),
            if (preview != null) Text('約 $preview kcal'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
        FilledButton(
          onPressed: _valid
              ? () {
                  final d = customDrink(_name.text, _abvValue!, _carbsValue);
                  final ml = _mlValue!;
                  Navigator.pop(context, _CartEntry(d, DrinkSize('${_countText(ml)}ml', ml, '杯'), 1));
                }
              : null,
          child: const Text('追加'),
        ),
      ],
    );
  }
}
