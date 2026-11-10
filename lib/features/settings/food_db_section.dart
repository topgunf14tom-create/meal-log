import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/food_db.dart';
import '../../data/entities.dart';

/// 記録の設定：1日の区切り時刻・撮影ガイド
class RecordPrefsSection extends StatefulWidget {
  const RecordPrefsSection({super.key});

  @override
  State<RecordPrefsSection> createState() => _RecordPrefsSectionState();
}

class _RecordPrefsSectionState extends State<RecordPrefsSection> {
  AppServices get s => AppServices.I;

  @override
  Widget build(BuildContext context) {
    final h = s.settings.dayStartHour;
    final small = Theme.of(context).textTheme.bodySmall;
    return Card(
      child: Column(
        children: [
          ListTile(
            title: const Text('1日の区切り'),
            subtitle: Text(h == 0 ? '0時（通常）' : '${24 + h}時区切り（翌$h時までの食事は前日分）', style: small),
            trailing: DropdownButton<int>(
              value: h,
              items: [
                for (var i = 0; i <= 6; i++) DropdownMenuItem(value: i, child: Text(i == 0 ? '0時' : '${24 + i}時')),
              ],
              onChanged: (v) async {
                if (v == null) return;
                await s.settings.set('day_start_hour', v);
                if (mounted) setState(() {});
              },
            ),
          ),
          ListTile(
            title: const Text('写真の撮影ガイドをまた表示する'),
            subtitle: Text('100円玉・真上＋斜め45°の説明', style: small),
            trailing: TextButton(
              onPressed: () async {
                await s.settings.remove('photo_guide_hidden');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('次の撮影で表示します')));
                }
              },
              child: const Text('戻す'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 食品データベースの収録状況・出典表記・登録食品の管理
class FoodDbSection extends StatefulWidget {
  const FoodDbSection({super.key});

  @override
  State<FoodDbSection> createState() => _FoodDbSectionState();
}

class _FoodDbSectionState extends State<FoodDbSection> {
  FoodDb? _db;

  @override
  void initState() {
    super.initState();
    AppServices.I.foods.ready.then((db) {
      if (mounted) setState(() => _db = db);
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = _db;
    final small = Theme.of(context).textTheme.bodySmall;
    if (db == null) return const Card(child: Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()));
    final m = db.meta;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: const Text('アプリ内の食品DB（端末に保存・通信なし）'),
            subtitle: Text(
              'チェーン店 ${m['chains_count']}社 ${db.countOf(FoodSource.chain)}品（${m['chains_generated_at']}）\n'
              '食品成分表 ${db.countOf(FoodSource.seibun)}食品\n'
              '居酒屋の定番 ${db.countOf(FoodSource.izakaya)}品・朝食の定番 ${db.countOf(FoodSource.breakfast)}品（推定値）',
              style: small,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.bookmark_outline),
            title: Text('登録食品 ${db.countOf(FoodSource.personal)}件'),
            subtitle: Text('栄養成分表示から登録した商品・JAN。タップで一覧', style: small),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UserFoodsScreen()));
              if (mounted) setState(() {});
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              '出典：「日本食品標準成分表（八訂）増補2023年」（文部科学省）。'
              'チェーン店の値は各社の公式公表値（kcalのみ公表の店はPFC不明、または成分表の類似食品で補完した推定）。'
              '過去の記録は記録した時点の値のまま保存され、DBを更新しても再計算されません。',
              style: small,
            ),
          ),
        ],
      ),
    );
  }
}

/// 登録食品（個人DB）の一覧と削除
class UserFoodsScreen extends StatefulWidget {
  const UserFoodsScreen({super.key});

  @override
  State<UserFoodsScreen> createState() => _UserFoodsScreenState();
}

class _UserFoodsScreenState extends State<UserFoodsScreen> {
  List<UserFood>? _foods;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await AppServices.I.db.userFoods();
    if (mounted) setState(() => _foods = list);
  }

  Future<void> _delete(UserFood f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('「${f.name}」を削除しますか？'),
        content: const Text('過去の記録はそのまま残ります。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('削除')),
        ],
      ),
    );
    if (ok != true || f.id == null) return;
    await AppServices.I.foods.deleteUserFood(f.id!);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final foods = _foods;
    return Scaffold(
      appBar: AppBar(title: const Text('登録食品')),
      body: foods == null
          ? const Center(child: CircularProgressIndicator())
          : foods.isEmpty
              ? const Center(child: Text('まだありません。記録画面の「栄養成分表示を撮る」で登録できます'))
              : ListView(
                  children: [
                    for (final f in foods)
                      ListTile(
                        title: Text(f.name),
                        subtitle: Text(
                          '${f.unitLabel}あたり ${f.kcal.round()} kcal'
                          '${f.protein == null ? '' : '  P${f.protein} F${f.fat} C${f.carbs}'}'
                          '${f.jan == null ? '' : '\nJAN ${f.jan}'}',
                        ),
                        trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(f)),
                      ),
                  ],
                ),
    );
  }
}
