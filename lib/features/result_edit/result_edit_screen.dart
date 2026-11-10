import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/food_db.dart';
import '../../core/format.dart';
import '../../core/links.dart';
import '../../core/meal_type.dart';
import '../../core/nutrition.dart';
import '../../core/photo_match.dart';
import '../../core/portion.dart';
import '../../data/entities.dart';
import '../../services/image_service.dart';
import '../../widgets/macro_widgets.dart';
import '../food/food_search_screen.dart';

/// 記録内容の確認・編集（新規記録と既存記録の編集で共用）。
/// DBから引いた品目（[drafts]）は量感クラス・個数・食べた割合をタップで直し、栄養値はコードで計算する。
/// 手入力・既存の記録（[items]）は従来どおり数値を直接編集する。
class ResultEditScreen extends StatefulWidget {
  const ResultEditScreen({
    super.key,
    required this.date,
    required this.mealType,
    this.items = const [],
    this.drafts = const [],
    this.photoBytes,
    this.sidePhotoBytes,
    this.photoPath,
    this.modelUsed,
    this.note,
    this.hint,
    this.mealId,
    this.createdAt,
    this.judgementJson,
    this.photoHash,
  });

  ResultEditScreen.edit({super.key, required Meal meal})
      : date = meal.date,
        mealType = meal.type,
        items = meal.items,
        drafts = const [],
        photoBytes = null,
        sidePhotoBytes = null,
        photoPath = meal.photoPath,
        modelUsed = meal.modelUsed,
        note = meal.note,
        hint = null,
        mealId = meal.id,
        createdAt = meal.createdAt,
        judgementJson = null,
        photoHash = null;

  final String date;
  final MealType mealType;
  final List<MealItem> items;
  final List<PortionDraft> drafts;
  final Uint8List? photoBytes;
  final Uint8List? sidePhotoBytes;
  final String? photoPath;
  final String? modelUsed;
  final String? note;
  final String? hint;
  final int? mealId;
  final DateTime? createdAt;

  /// 写真判定の結果（訂正をテキストだけで送るため）
  final String? judgementJson;

  /// 写真のハッシュ（保存時に内容と紐づけ、同じ写真なら次回APIを使わない）
  final String? photoHash;

  @override
  State<ResultEditScreen> createState() => _ResultEditScreenState();
}

class _ResultEditScreenState extends State<ResultEditScreen> {
  late MealType _type = widget.mealType;
  late String? _model = widget.modelUsed;
  late String? _note = widget.note;
  late String? _judgement = widget.judgementJson;
  final _rows = <_Row>[];
  bool _busy = false;

  AppServices get s => AppServices.I;

  @override
  void initState() {
    super.initState();
    _rows.addAll(widget.drafts.map(_PortionRow.fromDraft));
    _rows.addAll(widget.items.map(_ItemRow.new));
    if (_rows.isEmpty) _rows.add(_ItemRow(MealItem.manual));
  }

  /// 表示中の TextField が外れてから破棄する
  void _disposeLater(Iterable<_Row> rows) {
    final list = List.of(rows);
    if (list.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final r in list) {
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

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 写真の行を新しい判定で置き換える（ほかの行は残す）
  void _replacePhotoRows(List<PortionDraft> drafts) {
    final old = _rows.where((r) => r is _PortionRow && r.fromPhoto).toList();
    _rows.removeWhere(old.contains);
    _disposeLater(old);
    _rows.insertAll(0, drafts.map(_PortionRow.fromDraft));
    if (_rows.isEmpty) _rows.add(_ItemRow(MealItem.manual));
  }

  /// 利用者が明示的に選んだときだけの再判定（設定の再解析モデル）
  Future<void> _rejudge() async {
    final bytes = await _photoBytes();
    if (bytes == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('写真を再判定'),
        content: Text('設定の再解析モデル（${s.settings.reanalyzeModel}）で判定し直します。写真から判定した品目は置き換わります。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('再判定')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final r = await s.nutrition.judgePhoto(bytes, side: widget.sidePhotoBytes, hint: widget.hint, reanalyze: true);
      final db = await s.foods.ready;
      if (!mounted) return;
      setState(() {
        _replacePhotoRows(matchJudgement(db, r.judgement));
        _model = r.model;
        _note = r.judgement.note;
        _judgement = r.judgement.toCompactString();
      });
    } catch (e) {
      _snack('再判定に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 訂正：画像は再送せず、前回の判定と訂正の文章だけを送る
  Future<void> _refine() async {
    final prev = _judgement;
    if (prev == null) return;
    final ctl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('AIに訂正を伝える'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: '例：右の皿は唐揚げではなくとんかつ。味噌汁は無し'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('送る（画像なし）')),
        ],
      ),
    );
    ctl.dispose();
    if (text == null || text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await s.nutrition.refineJudgement(prev, text);
      final db = await s.foods.ready;
      if (!mounted) return;
      setState(() {
        _replacePhotoRows(matchJudgement(db, r.judgement));
        _judgement = r.judgement.toCompactString();
        if (r.judgement.note != null) _note = r.judgement.note;
      });
    } catch (e) {
      _snack('訂正できませんでした: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 全品目を人数で割る（大皿の取り分け）
  Future<void> _splitByPeople() async {
    final n = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('何人で分けましたか？'),
        children: [
          for (final k in [1, 2, 3, 4, 5, 6, 8, 10])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, k),
              child: Text(k == 1 ? '1人（全部食べた）' : '$k人（1/$k）'),
            ),
        ],
      ),
    );
    if (n == null) return;
    setState(() {
      for (final r in _rows) {
        r.setRatio(1 / n);
      }
    });
  }

  Future<void> _saveFavorite() async {
    final items = _collectItems();
    if (items.isEmpty) return;
    final ctl = TextEditingController(text: items.map((i) => i.name).join('＋'));
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('「いつもの」に登録'),
        content: TextField(controller: ctl, decoration: const InputDecoration(labelText: 'ホームに表示する名前')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('登録')),
        ],
      ),
    );
    ctl.dispose();
    if (name == null || name.isEmpty) return;
    await s.db.saveFavorite(Favorite(name: name, items: items, mealType: _type.name));
    _snack('「$name」をいつものに登録しました。ホームから1タップで記録できます');
  }

  List<MealItem> _collectItems() =>
      _rows.map((r) => r.toItem()).whereType<MealItem>().where((i) => i.name.isNotEmpty).toList();

  Future<void> _save() async {
    final unresolved = _rows.whereType<_PortionRow>().where((r) => r.portion == null).toList();
    if (unresolved.isNotEmpty) {
      _snack('「${unresolved.first.label}」はDBに見つかりませんでした。検索して選ぶか、削除してください');
      return;
    }
    final pending = _rows.whereType<_PortionRow>().where((r) => r.needsConfirm && !r.confirmed).toList();
    if (pending.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('確認が必要な品目があります'),
          content: Text('${pending.map((r) => r.portion!.food.displayName).join('、')}\n\n'
              '写真からの判定に自信が低い品目です。料理と量が合っていれば、そのまま記録できます。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('見直す')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('確認済みにして記録')),
          ],
        ),
      );
      if (ok != true) return;
      for (final r in pending) {
        r.confirmed = true;
      }
    }
    final items = _collectItems();
    if (items.isEmpty) {
      _snack('料理名を1つ以上入力してください');
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
      if (widget.mealId == null) await s.foods.recordUsage(items);
      if (widget.photoHash != null) await s.db.savePhotoHash(widget.photoHash!, items);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack('保存できませんでした: $e');
      }
    }
  }

  /// 品目の食品を差し替える（検索して選ぶ）
  Future<void> _changeFood(_PortionRow row, {String? query}) async {
    final picked = await Navigator.of(context).push<FoodRecord>(MaterialPageRoute(
      builder: (_) => FoodSearchScreen(
        date: widget.date,
        pickOne: true,
        initialQuery: query ?? row.label,
        title: '「${row.label}」に当たる食品を選ぶ',
      ),
    ));
    if (picked == null || !mounted) return;
    setState(() {
      final old = row.portion;
      row.portion = old == null
          ? Portion(food: picked, sizeClass: s.foods.lastClass[picked.ref] ?? sizeNormal)
          : old.copyWith(food: picked, clearManualGrams: true, clearPfcFrom: true);
      row.needsConfirm = false;
      row.syncGrams();
    });
  }

  /// 候補名で照合し直す
  Future<void> _useCandidate(_PortionRow row, String name) async {
    final db = await s.foods.ready;
    final hit = db.bestMatch([name]);
    if (!mounted) return;
    if (hit == null) {
      await _changeFood(row, query: name);
      return;
    }
    setState(() {
      row.label = name;
      final old = row.portion;
      row.portion = old == null ? Portion(food: hit.food) : old.copyWith(food: hit.food, clearPfcFrom: true);
      row.needsConfirm = hit.tier >= 2;
      row.syncGrams();
    });
  }

  /// kcal のみ公表の食品の PFC を、成分表の類似食品で補完する
  Future<void> _pickPfcSource(_PortionRow row) async {
    final p = row.portion;
    if (p == null) return;
    final picked = await Navigator.of(context).push<FoodRecord>(MaterialPageRoute(
      builder: (_) => FoodSearchScreen(
        date: widget.date,
        pickOne: true,
        initialQuery: p.food.name,
        sources: const {FoodSource.seibun, FoodSource.izakaya, FoodSource.breakfast},
        title: 'PFCの比率を借りる類似食品',
      ),
    ));
    if (picked == null || !mounted) return;
    setState(() => row.portion = p.copyWith(pfcFrom: picked));
  }

  Future<void> _ratioCustom(_Row row) async {
    final ctl = TextEditingController(text: '${(row.ratio * 100).round()}');
    final v = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('食べた割合'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: '%'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('キャンセル')),
          FilledButton(
            onPressed: () {
              final n = double.tryParse(ctl.text.trim());
              Navigator.pop(c, n == null ? null : (n / 100).clamp(0.01, 5.0).toDouble());
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (v != null) setState(() => row.setRatio(v));
  }

  Widget _ratioMenu(_Row row) => PopupMenuButton<double>(
        tooltip: '取り分け・残した分',
        onSelected: (v) {
          if (v < 0) {
            _ratioCustom(row);
          } else {
            setState(() => row.setRatio(v));
          }
        },
        itemBuilder: (_) => [
          for (final p in ratioPresets) PopupMenuItem(value: p.$2, child: Text(p.$1 == '全部' ? '全部食べた' : p.$1)),
          const PopupMenuItem(value: -1, child: Text('割合を入力…')),
        ],
        child: Chip(
          avatar: const Icon(Icons.pie_chart_outline, size: 16),
          label: Text(row.ratio == 1 ? '食べた割合：全部' : '食べた割合：${ratioLabel(row.ratio)}'),
          visualDensity: VisualDensity.compact,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final items = _rows.map((r) => r.toItem()).whereType<MealItem>();
    final total = Pfc.sum(items);
    final photoRows = _rows.any((r) => r is _PortionRow && r.fromPhoto);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mealId == null ? '内容を確認して記録' : '記録を編集'),
        actions: [
          IconButton(tooltip: '人数で分ける', icon: const Icon(Icons.groups_outlined), onPressed: _busy ? null : _splitByPeople),
          IconButton(tooltip: '「いつもの」に登録', icon: const Icon(Icons.star_outline), onPressed: _busy ? null : _saveFavorite),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
            children: [
              if (widget.photoBytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(widget.photoBytes!, height: 180, fit: BoxFit.cover),
                )
              else if (widget.photoPath != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(widget.photoPath!),
                      height: 180, fit: BoxFit.cover, errorBuilder: (context, error, stack) => const SizedBox.shrink()),
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
              if (photoRows)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '写真からは料理と量だけを判定し、栄養値は食品DBから計算しています（推定）。'
                    '量が違えば 少なめ／普通／多め／大盛 をタップ。'
                    '${_model != null && _model != 'manual' ? '\n判定：$_model' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 8),
              for (var i = 0; i < _rows.length; i++)
                switch (_rows[i]) {
                  final _PortionRow r => _PortionCard(
                      key: ObjectKey(r),
                      row: r,
                      onChanged: () => setState(() {}),
                      onChangeFood: () => _changeFood(r),
                      onCandidate: (name) => _useCandidate(r, name),
                      onPickPfc: () => _pickPfcSource(r),
                      ratioMenu: _ratioMenu(r),
                      onToPlain: () => setState(() {
                        final item = r.toItem();
                        if (item == null) return;
                        _rows[_rows.indexOf(r)] = _ItemRow(item);
                        _disposeLater([r]);
                      }),
                      onDelete: _rows.length <= 1 ? null : () => setState(() => _disposeLater([_rows.removeAt(i)])),
                    ),
                  final _ItemRow r => _ItemCard(
                      key: ObjectKey(r),
                      row: r,
                      ratioMenu: _ratioMenu(r),
                      onChanged: () => setState(() {}),
                      onDelete: _rows.length <= 1 ? null : () => setState(() => _disposeLater([_rows.removeAt(i)])),
                    ),
                },
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      final picked = await Navigator.of(context).push<List<Portion>>(
                        MaterialPageRoute(builder: (_) => FoodSearchScreen(date: widget.date)),
                      );
                      if (picked == null || !mounted) return;
                      setState(() => _rows.addAll(picked.map((p) => _PortionRow(portion: p, label: p.food.displayName))));
                    },
                    icon: const Icon(Icons.search),
                    label: const Text('食品を検索して追加'),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _rows.add(_ItemRow(MealItem.manual))),
                    icon: const Icon(Icons.edit_note),
                    label: const Text('手入力で追加'),
                  ),
                ],
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
                  if (_judgement != null) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _refine,
                        icon: const Icon(Icons.chat_outlined),
                        label: const Text('AIに訂正'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else if (_hasPhoto && photoRows) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _rejudge,
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('再判定'),
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
              if (_judgement != null && _hasPhoto)
                TextButton(
                  onPressed: _busy ? null : _rejudge,
                  child: const Text('写真ごと再判定する（再解析モデル）'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- 行 ----------

sealed class _Row {
  double get ratio;
  void setRatio(double r);
  MealItem? toItem();
  void dispose() {}
}

/// DBから引いた品目（量はクラス・個数・割合で決め、栄養値は計算する）
class _PortionRow extends _Row {
  _PortionRow({
    this.portion,
    required this.label,
    this.candidates = const [],
    this.needsConfirm = false,
    this.fromPhoto = false,
  }) {
    syncGrams();
  }

  factory _PortionRow.fromDraft(PortionDraft d) => _PortionRow(
        portion: d.portion,
        label: d.label,
        candidates: d.candidates,
        needsConfirm: d.needsConfirm,
        fromPhoto: d.fromPhoto,
      );

  Portion? portion;
  String label;
  final List<String> candidates;
  bool needsConfirm;
  bool confirmed = false;
  final bool fromPhoto;
  final grams = TextEditingController();

  /// 計量グラム欄を今の値に合わせる
  void syncGrams() {
    final g = portion?.manualGrams;
    grams.text = g == null ? '' : fmtNum(g);
  }

  @override
  double get ratio => portion?.ratio ?? 1;

  @override
  void setRatio(double r) {
    final p = portion;
    if (p != null) portion = p.copyWith(ratio: r);
  }

  /// 表示・記録する名前
  String get displayName {
    final f = portion?.food;
    if (f == null) return label;
    if (fromPhoto && f.source == FoodSource.seibun) return label;
    if (f.chain != null) return '${f.chain} ${f.displayName}';
    return f.displayName;
  }

  @override
  MealItem? toItem() {
    final p = portion;
    if (p == null) return null;
    final f = p.food;
    final r = computePortion(p);
    final notes = [
      if (fromPhoto) '写真判定',
      if (fromPhoto && f.source == FoodSource.seibun) '成分表「${f.name}」',
      ...r.notes,
    ];
    final String sourceType;
    if (f.source == FoodSource.chain) {
      sourceType = 'official';
    } else if (fromPhoto || f.estimated) {
      sourceType = 'estimate';
    } else {
      sourceType = 'reference';
    }
    return MealItem(
      name: displayName,
      amount: f.per100g ? (r.grams ?? 0) : p.count * p.ratio,
      unit: f.per100g ? 'g' : (f.source == FoodSource.chain ? '食' : '人前'),
      grams: r.grams,
      kcal: r.kcal,
      protein: r.protein,
      fat: r.fat,
      carbs: r.carbs,
      confidence: (needsConfirm && !confirmed) ? 'low' : (fromPhoto ? 'medium' : 'high'),
      sourceType: sourceType,
      sourceUrl: f.sourceUrl,
      foodRef: f.ref,
      sizeClass: p.usesSizeClass ? p.sizeClass : null,
      ratio: p.ratio,
      detail: notes.isEmpty ? null : notes.join('、'),
      pfcUnknown: r.pfcUnknown,
    );
  }

  @override
  void dispose() => grams.dispose();
}

/// 手入力・既存の記録の品目（数値を直接編集する）。量を変えると base に対する比で自動計算する
class _ItemRow extends _Row {
  _ItemRow(MealItem item)
      : base = item,
        _ratio = item.ratio,
        name = TextEditingController(text: item.name),
        amount = TextEditingController(text: fmtNum(item.amount)),
        unit = TextEditingController(text: item.unit),
        grams = TextEditingController(text: item.grams == null ? '' : fmtNum(item.grams!)),
        kcal = TextEditingController(text: kcal0(item.kcal)),
        p = TextEditingController(text: g1(item.protein)),
        f = TextEditingController(text: g1(item.fat)),
        c = TextEditingController(text: g1(item.carbs));

  MealItem base;
  double _ratio;
  final TextEditingController name, amount, unit, grams, kcal, p, f, c;

  static double _num(String s, double fallback) => double.tryParse(s.trim()) ?? fallback;

  @override
  double get ratio => _ratio;

  /// 食べた割合を変える（今の値を 新/旧 倍にする）
  @override
  void setRatio(double r) {
    if (_ratio <= 0 || r == _ratio) return;
    final cur = value;
    final scaled = cur.scaled(r / _ratio);
    _ratio = r;
    base = scaled;
    amount.text = fmtNum(double.parse(scaled.amount.toStringAsFixed(2)));
    if (scaled.grams != null) grams.text = fmtNum(double.parse(scaled.grams!.toStringAsFixed(1)));
    kcal.text = kcal0(scaled.kcal);
    p.text = g1(scaled.protein);
    f.text = g1(scaled.fat);
    c.text = g1(scaled.carbs);
  }

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
      foodRef: base.foodRef,
      sizeClass: base.sizeClass,
      ratio: _ratio,
      detail: base.detail,
      pfcUnknown: base.pfcUnknown,
    );
  }

  @override
  MealItem? toItem() => value;

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

  @override
  void dispose() {
    for (final t in [name, amount, unit, grams, kcal, p, f, c]) {
      t.dispose();
    }
  }
}

// ---------- カード ----------

class _PortionCard extends StatelessWidget {
  const _PortionCard({
    super.key,
    required this.row,
    required this.onChanged,
    required this.onChangeFood,
    required this.onCandidate,
    required this.onPickPfc,
    required this.onToPlain,
    required this.ratioMenu,
    this.onDelete,
  });

  final _PortionRow row;
  final VoidCallback onChanged;
  final VoidCallback onChangeFood;
  final void Function(String) onCandidate;
  final VoidCallback onPickPfc;
  final VoidCallback onToPlain;
  final Widget ratioMenu;
  final VoidCallback? onDelete;

  void _update(Portion p) {
    row.portion = p;
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = row.portion;
    final small = theme.textTheme.bodySmall;
    final f = p?.food;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: (row.needsConfirm && !row.confirmed) || p == null
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: p == null ? scheme.error : Colors.orange, width: 1.2),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onChangeFood,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(row.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          if (f != null)
                            Text(
                              row.fromPhoto && f.source == FoodSource.seibun
                                  ? '成分表：${f.name}'
                                  : f.subtitle,
                              style: small,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(tooltip: '食品を選び直す', icon: const Icon(Icons.manage_search), onPressed: onChangeFood),
                if (onDelete != null) IconButton(icon: const Icon(Icons.close), onPressed: onDelete),
              ],
            ),
            if (row.candidates.isNotEmpty)
              Wrap(
                spacing: 6,
                children: [
                  for (final c in row.candidates.where((c) => c != row.label))
                    ActionChip(
                      label: Text(c),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onCandidate(c),
                    ),
                ],
              ),
            if (p == null) ...[
              const SizedBox(height: 4),
              Text('食品DBに見つかりませんでした。検索して近いものを選んでください', style: TextStyle(color: scheme.error)),
              const SizedBox(height: 4),
              FilledButton.tonalIcon(onPressed: onChangeFood, icon: const Icon(Icons.search), label: const Text('検索して選ぶ')),
            ] else
              ..._details(context, p, computePortion(p)),
          ],
        ),
      ),
    );
  }

  List<Widget> _details(BuildContext context, Portion p, PortionResult r) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.bodySmall;
    return [
              const SizedBox(height: 6),
              if (p.usesSizeClass)
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: [
                    for (var i = 0; i < 4; i++) ButtonSegment(value: i, label: Text(sizeClassLabels[i])),
                  ],
                  selected: (p.manualGrams != null && p.usesManualGrams) ? <int>{} : {p.sizeClass},
                  emptySelectionAllowed: true,
                  onSelectionChanged: (sel) {
                    if (sel.isEmpty) return;
                    row.grams.clear();
                    _update(p.copyWith(sizeClass: sel.first, clearManualGrams: true));
                  },
                ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (p.usesCount)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: p.count > 0.5 ? () => _update(p.copyWith(count: p.count - 0.5)) : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text('${fmtNum(p.count)} ${p.food.source == FoodSource.chain ? '食' : '人前'}'),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _update(p.copyWith(count: p.count + 0.5)),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  if (p.usesManualGrams)
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: row.grams,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: '計量（任意）',
                          suffixText: 'g',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) {
                          final n = double.tryParse(v.trim());
                          _update(n == null || n <= 0 ? p.copyWith(clearManualGrams: true) : p.copyWith(manualGrams: n));
                        },
                      ),
                    ),
                  ratioMenu,
                  if (!p.food.alreadyCooked)
                    PopupMenuButton<CookMethod>(
                      tooltip: '調理法（見えない油・砂糖を加算）',
                      onSelected: (m) => _update(p.copyWith(cook: m)),
                      itemBuilder: (_) => [
                        for (final m in CookMethod.values)
                          PopupMenuItem(
                            value: m,
                            child: Text(m.addon == null ? m.label : '${m.label}（＋${m.addon!.label}）'),
                          ),
                      ],
                      child: Chip(
                        avatar: const Icon(Icons.local_fire_department_outlined, size: 16),
                        label: Text('調理：${p.cook.label}'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
              if (p.food.pfcUnknown)
                Row(
                  children: [
                    Icon(Icons.help_outline, size: 16, color: p.pfcFrom == null ? Colors.orange : scheme.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        p.pfcFrom == null ? '公式はkcalのみ公表。PFCは不明' : 'PFC補完：${p.pfcFrom!.name}',
                        style: small,
                      ),
                    ),
                    if (p.pfcFrom != null)
                      TextButton(onPressed: () => _update(p.copyWith(clearPfcFrom: true)), child: const Text('外す')),
                    TextButton(onPressed: onPickPfc, child: Text(p.pfcFrom == null ? '類似食品で補完' : '変える')),
                  ],
                ),
              const SizedBox(height: 4),
              Text(
                '${kcal0(r.kcal)} kcal   P ${g1(r.protein)}  F ${g1(r.fat)}  C ${g1(r.carbs)}'
                '${r.pfcUnknown ? '（PFC不明）' : ''}   ${portionAmountText(p, r)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (r.notes.isNotEmpty) Text(r.notes.join('、'), style: small),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  InfoChip(p.food.source.label),
                  if (row.fromPhoto || p.food.estimated) const InfoChip('推定'),
                  if (row.needsConfirm && !row.confirmed) ...[
                    const InfoChip('要確認', color: Colors.orange),
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () {
                        row.confirmed = true;
                        onChanged();
                      },
                      child: const Text('これで合っている'),
                    ),
                  ],
                  if (p.food.sourceUrl != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => openUrl(p.food.sourceUrl!),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('出典'),
                    ),
                  TextButton(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: onToPlain,
                    child: const Text('数値を直接編集'),
                  ),
                ],
              ),
    ];
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({super.key, required this.row, required this.onChanged, required this.ratioMenu, this.onDelete});

  final _ItemRow row;
  final VoidCallback onChanged;
  final Widget ratioMenu;
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
                ratioMenu,
                InfoChip(sourceLabel(b.sourceType)),
                if (b.sourceType != 'manual')
                  InfoChip(
                    confidenceLabel(b.confidence),
                    color: b.confidence == 'low' ? Theme.of(context).colorScheme.error : null,
                  ),
                if (b.pfcUnknown) const InfoChip('PFC不明', color: Colors.orange),
                if (b.sourceUrl != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => openUrl(b.sourceUrl!),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('出典'),
                  ),
              ],
            ),
            if (b.detail != null) Text(b.detail!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
