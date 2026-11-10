import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_services.dart';
import '../../core/dates.dart';
import '../../core/format.dart';
import '../../core/meal_type.dart';
import '../../core/nutrition.dart';
import '../../core/theme.dart';
import '../../data/entities.dart';
import '../../services/health_service.dart';
import '../../services/image_service.dart';
import '../../widgets/activity_card.dart';
import '../../widgets/macro_widgets.dart';
import '../record/record_screen.dart';
import '../result_edit/result_edit_screen.dart';
import '../../services/home_widget_updater.dart';
import '../history/exercise_history_screen.dart';
import '../settings/health_connect.dart';
import '../settings/settings_screen.dart';

/// タブでホームに戻ったときに読み直すための合図。
final homeReload = ValueNotifier<int>(0);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late DateTime _day = _today();
  List<Meal> _meals = [];
  List<Favorite> _favorites = [];
  Goal? _goal;
  ActivityDay? _activity;
  bool _healthAvailable = false;

  AppServices get s => AppServices.I;

  /// 1日の区切り時刻を考慮した今日
  DateTime _today() => logicalDay(DateTime.now(), AppServices.I.settings.dayStartHour);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    s.activity.revision.addListener(_load);
    homeReload.addListener(_load);
    _load();
    _initHealth();
    s.backup.autoBackupIfDue();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    s.activity.revision.removeListener(_load);
    homeReload.removeListener(_load);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _sync();
      s.backup.autoBackupIfDue();
      afterDataChanged();
    }
  }

  Future<void> _initHealth() async {
    await _showLastCrash();
    final st = await s.health.status();
    if (!mounted) return;
    setState(() => _healthAvailable = st == HealthStatus.available);
    await _sync();
  }

  /// 前回アプリが落ちていたら、その原因を表示する（コピーして送れるように）
  Future<void> _showLastCrash() async {
    final text = await s.health.lastCrash();
    if (text == null || text.isEmpty || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('前回アプリが終了した原因'),
        content: SingleChildScrollView(
          child: SelectableText(text, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (c.mounted) Navigator.pop(c);
            },
            child: const Text('コピーして閉じる'),
          ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('閉じる')),
        ],
      ),
    );
  }

  /// ヘルスコネクトから取り込み（連携オフなら何もしない）。取り込み後は revision 経由で再読み込み
  Future<void> _sync({bool force = false}) async {
    final msg = await s.activity.sync(force: force, days: [_day]);
    if (force && msg != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _load() async {
    final d = ymd(_day);
    final meals = await s.db.mealsOn(d);
    final goal = await s.db.goalOn(d);
    final activity = await s.db.activityOn(d);
    final favorites = await s.db.favorites();
    if (!mounted) return;
    setState(() {
      _favorites = favorites;
      _meals = meals;
      _goal = goal;
      _activity = activity;
    });
    afterDataChanged();
  }

  Future<void> _dayChanged() async {
    await _load();
    if (_activity == null) await _sync();
  }

  Future<void> _connect() async {
    await connectHealth(context);
    if (mounted) setState(() {});
  }

  Future<void> _dismissPrompt() async {
    await s.settings.set('health_prompt_dismissed', 'true');
    if (mounted) setState(() {});
  }

  void _shift(int days) {
    setState(() => _day = addDays(_day, days));
    _dayChanged();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: addDays(_today(), 1),
    );
    if (picked != null) {
      setState(() => _day = dayOnly(picked));
      _dayChanged();
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

  /// 「いつもの」を1タップで記録（取り消しはスナックバーから）
  Future<void> _quickLog(Favorite f) async {
    final type = guessMealType(DateTime.now());
    final id = await s.db.saveMeal(Meal(
      date: ymd(_day),
      type: type,
      createdAt: DateTime.now(),
      modelUsed: 'favorite',
      note: 'いつもの「${f.name}」',
      items: f.items,
    ));
    if (f.id != null) await s.db.bumpFavorite(f.id!);
    await s.foods.recordUsage(f.items);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${type.label}に「${f.name}」を記録しました（${kcal0(f.kcal)} kcal）'),
      action: SnackBarAction(
        label: '取り消す',
        onPressed: () async {
          await s.db.deleteMeal(id);
          await _load();
        },
      ),
    ));
  }

  Future<void> _deleteFavorite(Favorite f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('「${f.name}」をいつものから外しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('外す')),
        ],
      ),
    );
    if (ok != true || f.id == null) return;
    await s.db.deleteFavorite(f.id!);
    await _load();
  }

  /// 1日の記録をプレーンテキストで共有・コピー（スクリーンショットの代わり）
  Future<void> _shareText() async {
    final goal = _goal;
    if (goal == null) return;
    final healthOn = s.settings.healthEnabled;
    final burn = (healthOn && s.settings.addBurnToGoal) ? (_activity?.totalKcal ?? 0) : 0.0;
    final text = dayText(day: _day, meals: _meals, goal: goal, burn: burn);
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('1日の記録（テキスト）'),
        content: SingleChildScrollView(child: SelectableText(text, style: const TextStyle(fontSize: 12))),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (c.mounted) Navigator.pop(c);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('コピーしました')));
              }
            },
            child: const Text('コピー'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(c);
              await SharePlus.instance.share(ShareParams(text: text));
            },
            child: const Text('共有'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isToday = ymd(_day) == ymd(_today());
    final total = Pfc.sum(_meals.expand((m) => m.items));
    final goal = _goal;
    final healthOn = s.settings.healthEnabled;
    final burn = healthOn ? _activity?.totalKcal : null;
    final showPrompt = !healthOn && _healthAvailable && !s.settings.healthPromptDismissed;

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
            tooltip: 'テキストで共有',
            icon: const Icon(Icons.ios_share),
            onPressed: _shareText,
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
              onRefresh: () async {
                await _load();
                await _sync(force: true);
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  _CalorieCard(
                    total: total,
                    goal: goal,
                    burn: (s.settings.addBurnToGoal && burn != null) ? burn : 0,
                  ),
                  const SizedBox(height: 12),
                  if (healthOn) ...[
                    ActivityCard(
                      activity: _activity,
                      onRefresh: () => _sync(force: true),
                      onHistory: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const ExerciseHistoryScreen())),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (showPrompt) ...[
                    _HealthPromptCard(onConnect: _connect, onDismiss: _dismissPrompt),
                    const SizedBox(height: 12),
                  ],
                  _PfcCard(total: total, goal: goal),
                  const SizedBox(height: 12),
                  if (_favorites.isNotEmpty) ...[
                    _FavoritesCard(favorites: _favorites, onTap: _quickLog, onLongPress: _deleteFavorite),
                    const SizedBox(height: 12),
                  ],
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

/// 「いつもの」：検索なしで1タップ記録
class _FavoritesCard extends StatelessWidget {
  const _FavoritesCard({required this.favorites, required this.onTap, required this.onLongPress});

  final List<Favorite> favorites;
  final void Function(Favorite) onTap;
  final void Function(Favorite) onLongPress;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('いつもの（タップで記録・長押しで外す）', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final f in favorites)
                  GestureDetector(
                    onLongPress: () => onLongPress(f),
                    child: ActionChip(
                      avatar: const Icon(Icons.bolt, size: 16),
                      label: Text('${f.name}  ${kcal0(f.kcal)}kcal'),
                      onPressed: () => onTap(f),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 1日の記録のテキスト（品目・kcal・PFC・合計・残り予算）
String dayText({required DateTime day, required List<Meal> meals, required Goal goal, double burn = 0}) {
  final b = StringBuffer('【${day.year}/${jpDate(day)} の食事】\n');
  for (final type in MealType.values) {
    final list = meals.where((m) => m.type == type).toList();
    if (list.isEmpty) continue;
    final sub = Pfc.sum(list.expand((m) => m.items));
    b.writeln('■${type.label}（${kcal0(sub.kcal)} kcal）');
    for (final i in list.expand((m) => m.items)) {
      final pfc = i.pfcUnknown ? 'PFC不明' : 'P${g1(i.protein)} F${g1(i.fat)} C${g1(i.carbs)}';
      b.writeln('・${i.name} ${kcal0(i.kcal)}kcal $pfc${i.sourceType == 'estimate' ? '（推定）' : ''}');
    }
  }
  final total = Pfc.sum(meals.expand((m) => m.items));
  final target = goal.targetKcal + burn.roundToDouble();
  final t = targetGrams(goal);
  b.writeln('合計 ${kcal0(total.kcal)} kcal  P${g1(total.p)} F${g1(total.f)} C${g1(total.c)}');
  b.writeln('目標 ${kcal0(target)} kcal${burn > 0 ? '（消費 ${kcal0(burn)} を上乗せ）' : ''}  P${g1(t.p)} F${g1(t.f)} C${g1(t.c)}');
  final rest = target - total.kcal;
  b.write(rest >= 0 ? '残り ${kcal0(rest)} kcal・脂質 ${g1(t.f - total.f)} g' : '${kcal0(-rest)} kcal オーバー');
  return b.toString();
}

class _HealthPromptCard extends StatelessWidget {
  const _HealthPromptCard({required this.onConnect, required this.onDismiss});

  final VoidCallback onConnect;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ヘルスコネクトと連携', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            const Text('InBody の体重・体脂肪、Strava の運動、歩数を自動で取り込み、消費カロリーを計算します'),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onDismiss, child: const Text('今はしない')),
                FilledButton.tonal(onPressed: onConnect, child: const Text('連携する')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CalorieCard extends StatelessWidget {
  const _CalorieCard({required this.total, required this.goal, this.burn = 0});

  final Pfc total;
  final Goal goal;

  /// 目標に上乗せする消費カロリー（ヘルスコネクト）
  final double burn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final target = goal.targetKcal + burn.roundToDouble();
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
                Text(' / ${kcal0(target)} kcal'),
                const Spacer(),
                Text(
                  remain >= 0 ? 'あと ${kcal0(remain)} kcal' : '${kcal0(-remain)} kcal オーバー',
                  style: TextStyle(color: remain >= 0 ? scheme.primary : scheme.error, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (burn > 0)
              Text('目標 ${goal.targetKcal} ＋ 消費 ${kcal0(burn)} kcal', style: Theme.of(context).textTheme.bodySmall),
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
