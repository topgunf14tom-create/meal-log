import 'dart:io';

import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/dates.dart';
import '../../core/format.dart';
import '../../core/meal_type.dart';
import '../../core/nutrition.dart';
import '../../core/theme.dart';
import '../../data/entities.dart';
import '../../services/image_service.dart';
import '../../widgets/macro_widgets.dart';
import '../record/record_screen.dart';
import '../result_edit/result_edit_screen.dart';
import '../settings/settings_screen.dart';
import '../weight/weight_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _day = dayOnly(DateTime.now());
  List<Meal> _meals = [];
  Goal? _goal;

  AppServices get s => AppServices.I;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = ymd(_day);
    final meals = await s.db.mealsOn(d);
    final goal = await s.db.goalOn(d);
    if (!mounted) return;
    setState(() {
      _meals = meals;
      _goal = goal;
    });
  }

  void _shift(int days) {
    setState(() => _day = addDays(_day, days));
    _load();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: addDays(dayOnly(DateTime.now()), 1),
    );
    if (picked != null) {
      setState(() => _day = dayOnly(picked));
      _load();
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    await _load();
  }

  Future<void> _delete(Meal m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('この記録を削除しますか？'),
        content: Text(m.items.map((i) => i.name).join('、')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('削除')),
        ],
      ),
    );
    if (ok != true || m.id == null) return;
    await s.db.deleteMeal(m.id!);
    await ImageService.deleteFile(m.photoPath);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isToday = ymd(_day) == ymd(DateTime.now());
    final total = Pfc.sum(_meals.expand((m) => m.items));
    final goal = _goal;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
        titleSpacing: 0,
        title: InkWell(
          onTap: _pickDate,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('${jpDate(_day)}${isToday ? '  今日' : ''}'),
          ),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shift(1)),
          IconButton(
            tooltip: '体重',
            icon: const Icon(Icons.monitor_weight_outlined),
            onPressed: () => _open(const WeightScreen()),
          ),
          IconButton(
            tooltip: '設定',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _open(const SettingsScreen()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(RecordScreen(date: _day)),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('記録する'),
      ),
      body: goal == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  _CalorieCard(total: total, goal: goal),
                  const SizedBox(height: 12),
                  _PfcCard(total: total, goal: goal),
                  const SizedBox(height: 12),
                  for (final type in MealType.values)
                    _MealSection(
                      type: type,
                      meals: _meals.where((m) => m.type == type).toList(),
                      onTap: (m) => _open(ResultEditScreen.edit(meal: m)),
                      onDelete: _delete,
                    ),
                ],
              ),
            ),
    );
  }
}

class _CalorieCard extends StatelessWidget {
  const _CalorieCard({required this.total, required this.goal});

  final Pfc total;
  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final target = goal.targetKcal.toDouble();
    final remain = target - total.kcal;
    final ratio = target <= 0 ? 0.0 : (total.kcal / target).clamp(0.0, 1.0).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('摂取カロリー', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(kcal0(total.kcal), style: Theme.of(context).textTheme.headlineMedium),
                Text(' / ${goal.targetKcal} kcal'),
                const Spacer(),
                Text(
                  remain >= 0 ? 'あと ${kcal0(remain)} kcal' : '${kcal0(-remain)} kcal オーバー',
                  style: TextStyle(color: remain >= 0 ? scheme.primary : scheme.error, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 12,
                color: remain >= 0 ? scheme.primary : scheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PfcCard extends StatelessWidget {
  const _PfcCard({required this.total, required this.goal});

  final Pfc total;
  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final t = targetGrams(goal);
    final r = total.energyRatio();
    final small = Theme.of(context).textTheme.bodySmall;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Column(
              children: [
                PfcPie(p: r.p, f: r.f, c: r.c),
                const SizedBox(height: 8),
                Text('P${r.p.round()} F${r.f.round()} C${r.c.round()}', style: small),
                Text('目標 ${goal.pRatio}/${goal.fRatio}/${goal.cRatio}', style: small),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                children: [
                  MacroBar(label: 'P たんぱく質', value: total.p, target: t.p, color: MacroColors.protein),
                  const SizedBox(height: 10),
                  MacroBar(label: 'F 脂質', value: total.f, target: t.f, color: MacroColors.fat),
                  const SizedBox(height: 10),
                  MacroBar(label: 'C 炭水化物', value: total.c, target: t.c, color: MacroColors.carbs),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MealSection extends StatelessWidget {
  const _MealSection({required this.type, required this.meals, required this.onTap, required this.onDelete});

  final MealType type;
  final List<Meal> meals;
  final void Function(Meal) onTap;
  final void Function(Meal) onDelete;

  @override
  Widget build(BuildContext context) {
    final subtotal = Pfc.sum(meals.expand((m) => m.items));
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text(type.label, style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text('${kcal0(subtotal.kcal)} kcal'),
              ],
            ),
          ),
          if (meals.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text('記録なし', style: Theme.of(context).textTheme.bodySmall),
            ),
          for (final m in meals)
            ListTile(
              onTap: () => onTap(m),
              leading: _Thumb(path: m.photoPath),
              title: Text(m.items.map((i) => i.name).join('、'), maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Builder(builder: (_) {
                final p = Pfc.sum(m.items);
                return Text('${kcal0(p.kcal)} kcal  P${g1(p.p)} F${g1(p.f)} C${g1(p.c)}');
              }),
              trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => onDelete(m)),
            ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.restaurant, size: 20),
    );
    if (path == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        File(path!),
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        cacheWidth: 144,
        errorBuilder: (context, error, stack) => placeholder,
      ),
    );
  }
}
