import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/dates.dart';
import '../../core/text_normalize.dart';
import '../../data/entities.dart';

/// よく食べるもの：最近90日に記録した料理を回数の多い順に並べ、選んだものを返す
class FrequentScreen extends StatefulWidget {
  const FrequentScreen({super.key});

  @override
  State<FrequentScreen> createState() => _FrequentScreenState();
}

class _FrequentScreenState extends State<FrequentScreen> {
  List<FrequentItem>? _items;
  final _selected = <int>{};
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final since = ymd(DateTime.now().subtract(const Duration(days: 90)));
    final list = await AppServices.I.db.frequentItems(since: since, limit: 60);
    if (mounted) setState(() => _items = list);
  }

  void _done() {
    final list = _items ?? const <FrequentItem>[];
    final picked = [
      for (var i = 0; i < list.length; i++)
        if (_selected.contains(i)) list[i].item,
    ];
    Navigator.of(context).pop(picked);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final q = normalizeKey(_query.text);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('よく食べるもの')),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: _done,
                  child: Text('${_selected.length}品を記録する（${_selectedKcal().round()} kcal）'),
                ),
              ),
            ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('最近90日の記録がまだありません。\n記録した料理がここに並びます。', textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    TextField(
                      controller: _query,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: '料理名で絞り込む',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Text('タップで選んで、まとめて記録できます（APIは使いません）', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    for (var i = 0; i < items.length; i++)
                      if (q.isEmpty || normalizeKey(items[i].item.name).contains(q))
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _selected.contains(i),
                          onChanged: (v) => setState(() => v == true ? _selected.add(i) : _selected.remove(i)),
                          title: Text(items[i].item.name),
                          subtitle: Text(
                            '${_amountText(items[i].item)}・${items[i].item.kcal.round()} kcal'
                            '・P${items[i].item.protein.toStringAsFixed(1)} F${items[i].item.fat.toStringAsFixed(1)} '
                            'C${items[i].item.carbs.toStringAsFixed(1)}\n${items[i].count}回・最後 ${shortDate(parseYmd(items[i].lastDate))}',
                          ),
                          isThreeLine: true,
                        ),
                  ],
                ),
    );
  }

  double _selectedKcal() {
    final list = _items ?? const <FrequentItem>[];
    var sum = 0.0;
    for (final i in _selected) {
      if (i < list.length) sum += list[i].item.kcal;
    }
    return sum;
  }

  String _amountText(MealItem i) {
    final a = i.amount == i.amount.roundToDouble() ? i.amount.toInt().toString() : i.amount.toStringAsFixed(1);
    return '$a${i.unit}';
  }
}
