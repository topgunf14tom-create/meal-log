import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/food_db.dart';
import '../../core/format.dart';
import '../../core/portion.dart';
import 'day_budget.dart';

/// 食品の横断検索（チェーン公式値・成分表・居酒屋/朝食の定番・登録食品）。
/// 通信・API なしでインクリメンタルに候補を出し、タップ＋個数で記録する（経路A・D）。
/// [pickOne] なら1件選んで返す（料理の差し替え・PFC補完の類似食品選び）。
class FoodSearchScreen extends StatefulWidget {
  const FoodSearchScreen({
    super.key,
    required this.date,
    this.pickOne = false,
    this.initialQuery = '',
    this.sources,
    this.title,
  });

  final String date;
  final bool pickOne;
  final String initialQuery;
  final Set<FoodSource>? sources;
  final String? title;

  @override
  State<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends State<FoodSearchScreen> {
  late final _query = TextEditingController(text: widget.initialQuery);
  FoodDb? _db;
  DayBudget? _budget;
  int _people = 1;
  final _tray = <Portion>[];

  AppServices get s => AppServices.I;

  @override
  void initState() {
    super.initState();
    s.foods.ready.then((db) {
      if (mounted) setState(() => _db = db);
    });
    if (!widget.pickOne) {
      DayBudget.load(widget.date).then((b) {
        if (mounted) setState(() => _budget = b);
      });
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  double get _ratio => 1 / _people;

  /// よく使う食品（検索語が空のとき）
  List<FoodRecord> _recent(FoodDb db) {
    final refs = db.usage.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final out = <FoodRecord>[];
    for (final e in refs) {
      final f = db.byRef(e.key);
      if (f == null) continue;
      if (widget.sources != null && !widget.sources!.contains(f.source)) continue;
      out.add(f);
      if (out.length >= 30) break;
    }
    return out;
  }

  Portion _defaultPortion(FoodRecord f) => Portion(
        food: f,
        sizeClass: s.foods.lastClass[f.ref] ?? sizeNormal,
        ratio: _ratio,
      );

  void _tap(FoodRecord f) {
    if (widget.pickOne) {
      Navigator.of(context).pop(f);
      return;
    }
    setState(() {
      final i = _tray.indexWhere((p) => p.food.ref == f.ref);
      if (i >= 0 && _tray[i].usesCount) {
        _tray[i] = _tray[i].copyWith(count: _tray[i].count + 1);
      } else if (i < 0) {
        _tray.add(_defaultPortion(f));
      }
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('「${f.displayName}」を追加'), duration: const Duration(milliseconds: 900)));
  }

  void _setPeople(int n) {
    setState(() {
      _people = n.clamp(1, 20).toInt();
      for (var i = 0; i < _tray.length; i++) {
        _tray[i] = _tray[i].copyWith(ratio: _ratio);
      }
    });
  }

  double get _trayKcal => _tray.fold(0.0, (a, p) => a + computePortion(p).kcal);
  double get _trayFat => _tray.fold(0.0, (a, p) => a + computePortion(p).fat);

  Widget _budgetChip(PortionResult r) {
    final b = _budget;
    if (b == null) return const SizedBox.shrink();
    final rest = b.minus(_trayKcal, _trayFat);
    final fit = budgetFit(rest, r.kcal, r.pfcUnknown ? 0 : r.fat);
    final scheme = Theme.of(context).colorScheme;
    final (text, color) = switch (fit) {
      BudgetFit.ok => ('残り内', scheme.primary),
      BudgetFit.fatOver => ('脂質超', Colors.orange),
      BudgetFit.kcalOver => ('kcal超', scheme.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withAlpha(36), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  String _values(FoodRecord f) {
    final unit = f.per100g ? '/100g' : '';
    final k = '${kcal0(f.kcal ?? 0)} kcal$unit';
    if (f.pfcUnknown) return '$k・PFC不明';
    return '$k  P${g1(f.protein!)} F${g1(f.fat!)} C${g1(f.carbs!)}';
  }

  @override
  Widget build(BuildContext context) {
    final db = _db;
    final q = _query.text.trim();
    final results = db == null
        ? const <FoodRecord>[]
        : q.isEmpty
            ? _recent(db)
            : db.search(q, sources: widget.sources).map((h) => h.food).toList();
    final theme = Theme.of(context);
    final rest = _budget?.minus(_trayKcal, _trayFat);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? (widget.pickOne ? '食品を選ぶ' : '食品を検索して記録'))),
      bottomNavigationBar: widget.pickOne || _tray.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (var i = 0; i < _tray.length; i++)
                          InputChip(
                            label: Text(
                              '${_tray[i].food.displayName}${_tray[i].count != 1 ? ' ×${fmtNum(_tray[i].count)}' : ''}',
                              overflow: TextOverflow.ellipsis,
                            ),
                            onDeleted: () => setState(() => _tray.removeAt(i)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(List<Portion>.of(_tray)),
                      child: Text('${_tray.length}品を確認して記録（${kcal0(_trayKcal)} kcal）'),
                    ),
                  ],
                ),
              ),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: '例：からあげ、生中、すき家 牛丼、ファミチキ',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_query.clear),
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (!widget.pickOne)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.groups_outlined, size: 18),
                  const SizedBox(width: 4),
                  const Text('人数'),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: _people > 1 ? () => _setPeople(_people - 1) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_people', style: const TextStyle(fontWeight: FontWeight.bold)),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _setPeople(_people + 1),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  Expanded(
                    child: Text(
                      _people > 1 ? '大皿は 1/$_people で記録（あとで品ごとに変更可）' : '飲み会は人数をセット',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if (rest != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '今日の残り ${kcal0(rest.kcal)} kcal・脂質 ${g1(rest.fat)} g',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: db == null
                ? const Center(child: CircularProgressIndicator())
                : results.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            q.isEmpty ? '料理名・商品名・店名を入力してください' : '見つかりませんでした。ひらがなや短い語でも試してください',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: results.length + (q.isEmpty ? 1 : 0),
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          if (q.isEmpty && i == 0) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                              child: Text('よく使う食品', style: theme.textTheme.labelLarge),
                            );
                          }
                          final f = results[q.isEmpty ? i - 1 : i];
                          final r = computePortion(_defaultPortion(f));
                          final inTray = _tray.any((p) => p.food.ref == f.ref);
                          return ListTile(
                            dense: true,
                            onTap: () => _tap(f),
                            leading: Icon(
                              inTray ? Icons.check_circle : _icon(f.source),
                              color: inTray ? theme.colorScheme.primary : null,
                            ),
                            title: Text(f.displayName, maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${f.subtitle}\n${_values(f)}', maxLines: 3),
                            isThreeLine: true,
                            trailing: widget.pickOne ? null : _budgetChip(r),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  IconData _icon(FoodSource s) => switch (s) {
        FoodSource.personal => Icons.bookmark_outline,
        FoodSource.chain => Icons.storefront_outlined,
        FoodSource.izakaya => Icons.sports_bar_outlined,
        FoodSource.breakfast => Icons.free_breakfast_outlined,
        FoodSource.seibun => Icons.menu_book_outlined,
      };
}
