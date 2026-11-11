import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app_services.dart';
import '../../core/dates.dart';
import '../../core/food_db.dart';
import '../../core/image_hash.dart';
import '../../core/label_text.dart';
import '../../core/meal_type.dart';
import '../../core/photo_match.dart';
import '../../core/portion.dart';
import '../../core/theme.dart';
import '../../data/entities.dart';
import '../../services/image_service.dart';
import '../../services/nutrition_service.dart';
import '../food/food_search_screen.dart';
import '../result_edit/result_edit_screen.dart';
import '../settings/api_key_widgets.dart';
import 'alcohol_screen.dart';
import 'barcode_scan_screen.dart';
import 'frequent_screen.dart';
import 'label_confirm_screen.dart';

/// 記録方法を選ぶ画面
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, required this.date});

  final DateTime date;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  MealType _type = guessMealType(DateTime.now());
  final _hint = TextEditingController();
  bool _busy = false;
  String _busyLabel = '';

  AppServices get s => AppServices.I;

  @override
  void dispose() {
    _hint.dispose();
    super.dispose();
  }

  /// APIキーが無ければ設定を促す
  Future<bool> _ensureKey() async {
    if (await s.keys.hasKey()) return true;
    if (!mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('APIキーが未設定です'),
        content: const Text('写真解析とチェーン店検索には、あなたの Claude APIキーが必要です。今すぐ設定しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('あとで')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('設定する')),
        ],
      ),
    );
    if (go != true || !mounted) return false;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ApiKeyScreen()));
    return s.keys.hasKey();
  }

  Future<ImageSource?> _chooseSource() => showModalBottomSheet<ImageSource>(
        context: context,
        builder: (c) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('カメラで撮影'),
                onTap: () => Navigator.pop(c, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('アルバムから選ぶ'),
                onTap: () => Navigator.pop(c, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

  Future<Uint8List?> _pickPhoto() async {
    final src = await _chooseSource();
    if (src == null) return null;
    try {
      return await s.images.pick(src, maxSide: s.settings.maxSide, quality: s.settings.jpegQuality);
    } catch (e) {
      _snack('写真を読み込めませんでした: $e');
      return null;
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 撮影ガイド（100円玉・真上＋斜め45°）。「次から表示しない」で省略できる
  Future<bool> _photoGuide() async {
    if (s.settings.raw('photo_guide_hidden') == 'true') return true;
    var hide = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('撮影のしかた'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('1. 100円玉を料理と同じ面（テーブル）に置く。皿より手前に浮かせない\n'
                  '2. 1枚目：真上から（面積と大きさ）\n'
                  '3. 2枚目：斜め約45°から（盛りの高さ）。毎回だいたい同じ角度で\n\n'
                  '写真からは料理名と量だけを判定し、栄養値はアプリ内の食品DBで計算します。'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: hide,
                onChanged: (v) => setLocal(() => hide = v ?? false),
                title: const Text('次から表示しない'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('やめる')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('撮影する')),
          ],
        ),
      ),
    );
    if (hide) await s.settings.set('photo_guide_hidden', 'true');
    return ok == true;
  }

  /// 写真判定（経路C）：真上＋斜めの2枚 → Haiku 1コール → 食品DBで照合 → 量はクラスで確認
  /// 撮影の前に「いつも」の候補を出す（当たればタップだけで記録、APIなし）。記録したら true
  Future<bool> _suggestBeforePhoto() async {
    if (s.settings.raw('photo_suggest') == 'false') return false;
    final since = ymd(addDays(widget.date, -30));
    final repeated = await s.db.repeatedMeals(_type, since: since);
    final favs = (await s.db.favorites()).where((f) => f.mealType == null || f.mealType == _type.name).take(5).toList();
    final cands = <({String label, List<MealItem> items, String sub})>[
      for (final f in favs) (label: f.name, items: f.items, sub: 'いつもの'),
      for (final r in repeated)
        if (!favs.any((f) => f.items.map((i) => i.name).join('、') == r.label))
          (label: r.label, items: r.items, sub: '最近30日で${r.count}回'),
    ];
    if (cands.isEmpty || !mounted) return false;
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('この${_type.label}ですか？（タップで記録・APIなし）', style: Theme.of(c).textTheme.titleSmall),
            ),
            for (var i = 0; i < cands.length; i++)
              ListTile(
                leading: const Icon(Icons.bolt),
                title: Text(cands[i].label, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${cands[i].sub}・${cands[i].items.fold<double>(0, (a, x) => a + x.kcal).round()} kcal'),
                onTap: () => Navigator.pop(c, i),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(c, -1),
                icon: const Icon(Icons.photo_camera),
                label: const Text('違う・撮影する'),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return true; // 閉じた＝やめる
    if (picked < 0 || !mounted) return false;
    await _openEditor(items: cands[picked].items, model: 'manual', note: '候補から記録（API未使用）');
    return true;
  }

  Future<void> _photo() async {
    if (await _suggestBeforePhoto()) return;
    if (!mounted || !await _ensureKey()) return;
    if (!mounted || !await _photoGuide()) return;
    final top = await _pickPhoto();
    if (top == null || !mounted) return;

    // 同じ写真（前に確定した記録）なら API を使わずに前回の内容を出す
    final hash = await ImageService.photoHash(top);
    if (hash != null) {
      final reused = await _reusePhoto(hash, top);
      if (reused) return;
    }
    if (!mounted) return;

    final side = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('斜め45°の写真'),
        content: const Text('斜めからの2枚目があると、盛りの高さが分かり量の判定が安定します。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('1枚で判定')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('斜めも撮る')),
        ],
      ),
    );
    Uint8List? sideBytes;
    if (side == true) sideBytes = await _pickPhoto();
    if (!mounted) return;

    setState(() {
      _busy = true;
      _busyLabel = '料理と量を判定中…';
    });
    try {
      final r = await s.nutrition.judgePhoto(top, side: sideBytes, hint: _hint.text);
      final db = await s.foods.ready;
      final drafts = matchJudgement(db, r.judgement);
      if (!mounted) return;
      setState(() => _busy = false);
      await _openEditor(
        drafts: drafts,
        items: drafts.isEmpty ? [MealItem.manual] : const [],
        photo: top,
        sidePhoto: sideBytes,
        model: r.model,
        note: r.judgement.note,
        judgementJson: r.judgement.toCompactString(),
        photoHash: hash,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      await _failed(e, top);
    }
  }

  /// 前回確定した写真とほぼ同じなら、前回の内容を使うか尋ねる。使ったら true
  Future<bool> _reusePhoto(String hash, Uint8List photo) async {
    final list = await s.db.photoHashes();
    for (final (h, items) in list) {
      if (items.isEmpty || hammingHex(h, hash) > 4) continue;
      if (!mounted) return false;
      final use = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('前と同じ写真のようです'),
          content: Text('前回の内容「${items.map((i) => i.name).join('、')}」を使いますか？（APIを使いません）'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('判定し直す')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('前回の内容を使う')),
          ],
        ),
      );
      if (use != true) return false;
      await _openEditor(items: items, photo: photo, model: 'reuse', note: '前回の同じ写真の内容を再利用（API未使用）');
      return true;
    }
    return false;
  }

  Future<void> _failed(Object error, Uint8List? photo) async {
    final manual = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('判定できませんでした'),
        content: Text('$error'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('閉じる')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('検索・手入力する')),
        ],
      ),
    );
    if (manual == true) {
      await _openEditor(items: [MealItem.manual], photo: photo, model: 'manual');
    }
  }

  /// 食品を検索して記録（経路A・D。APIなし）
  Future<void> _search() async {
    final picked = await Navigator.of(context).push<List<Portion>>(
      MaterialPageRoute(builder: (_) => FoodSearchScreen(date: ymd(widget.date))),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    await _openEditor(
      drafts: [for (final p in picked) PortionDraft(portion: p, label: p.food.displayName)],
      model: 'manual',
    );
  }

  /// 栄養成分表示（経路B）：端末OCR → 整合性チェック → 落ちたら Haiku の転記。確認して登録食品に保存
  Future<FoodRecord?> _readLabel({String? jan}) async {
    final bytes = await _pickPhoto();
    if (bytes == null || !mounted) return null;
    setState(() {
      _busy = true;
      _busyLabel = '栄養成分表示を読み取り中…';
    });
    LabelValues? values;
    String? via;
    String? foundJan = jan;
    Object? error;
    try {
      final text = await s.ocr.readText(bytes);
      if (text != null) {
        final v = parseLabelText(text);
        if (v.consistent) {
          values = v;
          via = '端末の文字認識（API未使用）';
        }
      }
      if (values == null) {
        if (await s.keys.hasKey()) {
          final r = await s.nutrition.transcribeLabel(bytes);
          values = r.values;
          foundJan ??= r.jan;
          via = 'Haiku で転記';
        } else {
          error = '端末で読み取れず、APIキーも未設定です';
        }
      }
    } catch (e) {
      error = e;
    }
    if (!mounted) return null;
    setState(() => _busy = false);
    if (values == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('読み取れませんでした: $error')));
    }
    return Navigator.of(context).push<FoodRecord>(MaterialPageRoute(
      builder: (_) => LabelConfirmScreen(values: values ?? const LabelValues(), jan: foundJan, via: via),
    ));
  }

  Future<void> _label() async {
    final rec = await _readLabel();
    if (rec == null || !mounted) return;
    await _openEditor(
      drafts: [PortionDraft(portion: _labelPortion(rec), label: rec.displayName)],
      model: 'label',
    );
  }

  Portion _labelPortion(FoodRecord rec) =>
      Portion(food: rec, manualGrams: rec.per100g ? (rec.servingGrams ?? 100) : null);

  /// バーコード（JAN）：連続スキャンでまとめて1食に。登録済みは API なし、未登録はラベルを撮って登録
  Future<void> _barcode() async {
    final codes = await Navigator.of(context).push<List<ScannedCode>>(
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
    );
    if (codes == null || codes.isEmpty || !mounted) return;
    final db = await s.foods.ready;
    final drafts = <PortionDraft>[];
    for (final c in codes) {
      var rec = db.byJan(c.jan);
      if (rec == null) {
        if (!mounted) return;
        final go = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('未登録の商品'),
            content: Text('JAN ${c.jan}\nパッケージの栄養成分表示を撮って登録しますか？（2回目からは撮影不要）'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('この商品は飛ばす')),
              FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('表示を撮る')),
            ],
          ),
        );
        if (go == true) rec = await _readLabel(jan: c.jan);
      }
      if (rec != null) {
        final base = _labelPortion(rec);
        drafts.add(PortionDraft(portion: base.copyWith(count: c.count.toDouble()), label: rec.displayName));
      }
    }
    if (drafts.isEmpty || !mounted) return;
    await _openEditor(drafts: drafts, model: 'barcode');
  }

  Future<void> _chain() async {
    if (!await _ensureKey()) return;
    if (!mounted) return;
    final input = await showDialog<_ChainInput>(context: context, builder: (_) => const _ChainDialog());
    if (input == null) return;
    Uint8List? bytes;
    if (input.withPhoto) {
      bytes = await _pickPhoto();
      if (bytes == null) return;
    }
    await _analyze(
      '公式サイトの栄養成分を検索中…',
      () => s.nutrition.lookupChain(store: input.store, menu: input.menu, photo: bytes),
      bytes,
    );
  }

  Future<void> _alcohol() async {
    final items = await Navigator.of(context).push<List<MealItem>>(
      MaterialPageRoute(builder: (_) => const AlcoholScreen()),
    );
    if (items == null || items.isEmpty || !mounted) return;
    await _openEditor(items: items, model: 'manual');
  }

  Future<void> _frequent() async {
    final items = await Navigator.of(context).push<List<MealItem>>(
      MaterialPageRoute(builder: (_) => const FrequentScreen()),
    );
    if (items == null || items.isEmpty || !mounted) return;
    await _openEditor(items: items, model: 'manual');
  }

  /// 前回の同じ食事区分の内容をそのまま使う
  Future<void> _sameAsLast() async {
    final last = await s.db.lastMealOfType(_type, ymd(widget.date));
    if (!mounted) return;
    if (last == null || last.items.isEmpty) {
      _snack('${_type.label}の記録がまだありません');
      return;
    }
    await _openEditor(items: last.items, model: 'manual', note: '${jpDate(parseYmd(last.date))}の${_type.label}と同じ');
  }

  Future<void> _analyze(String label, Future<AnalysisResult> Function() job, Uint8List? photo) async {
    setState(() {
      _busy = true;
      _busyLabel = label;
    });
    AnalysisResult? result;
    Object? error;
    try {
      result = await job();
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    if (result != null) {
      final items = result.items.isEmpty ? [MealItem.manual] : result.items;
      await _openEditor(items: items, photo: photo, model: result.model, note: result.note);
      return;
    }
    await _failed(error ?? '不明なエラー', photo);
  }

  Future<void> _openEditor({
    List<MealItem> items = const [],
    List<PortionDraft> drafts = const [],
    Uint8List? photo,
    Uint8List? sidePhoto,
    String? model,
    String? note,
    String? judgementJson,
    String? photoHash,
  }) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ResultEditScreen(
        date: ymd(widget.date),
        mealType: _type,
        items: items,
        drafts: drafts,
        photoBytes: photo,
        sidePhotoBytes: sidePhoto,
        modelUsed: model,
        note: note,
        hint: _hint.text,
        judgementJson: judgementJson,
        photoHash: photoHash,
      ),
    ));
    if (saved == true && mounted) Navigator.of(context).pop(true);
  }

  /// 入力方法の行（カードにせず罫線で区切る）
  Widget _action(IconData icon, String title, String subtitle, VoidCallback onTap) => DecoratedBox(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          leading: Icon(icon, size: 26, color: AppColors.text),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle, style: const TextStyle(color: AppColors.sub, fontSize: 13)),
          trailing: const Icon(Icons.chevron_right, color: AppColors.faint),
          onTap: _busy ? null : onTap,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text('${jpDate(widget.date)} の記録')),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SegmentedButton<MealType>(
                  segments: [
                    for (final t in MealType.values) ButtonSegment(value: t, label: Text(t.label)),
                  ],
                  selected: {_type},
                  onSelectionChanged: (sel) => setState(() => _type = sel.first),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _sameAsLast,
                        icon: const Icon(Icons.replay),
                        label: Text('前回の${_type.label}と同じ'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _frequent,
                        icon: const Icon(Icons.star_outline),
                        label: const Text('よく食べるもの'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _action(Icons.search, '食品を検索して記録', 'チェーン店・成分表・居酒屋の定番から選ぶ（APIなし）', _search),
                _action(Icons.photo_camera, '写真で判定', '100円玉と一緒に真上＋斜めを撮影。料理と量だけAIが判定（Haiku）', _photo),
                _action(Icons.qr_code_scanner, 'バーコードで記録', '登録済みの商品はすぐ記録。続けて読み取ってまとめて1食に', _barcode),
                _action(Icons.receipt_long, '栄養成分表示を撮る', '端末で読み取り、読めなければHaikuで転記。登録して次回から撮影不要', _label),
                _action(Icons.sports_bar, 'お酒', 'ビール・ハイボール・ワインなどを選んで記録（APIキー不要）', _alcohol),
                _action(Icons.storefront, 'DBに無いチェーン店', '公式サイトの栄養成分をWeb検索（Sonnet＋Web検索）', _chain),
                _action(Icons.edit_note, '手入力', '料理名と栄養価を自分で入力',
                    () => _openEditor(items: [MealItem.manual], model: 'manual')),
                const SizedBox(height: 16),
                TextField(
                  controller: _hint,
                  decoration: const InputDecoration(
                    labelText: '補足（任意）',
                    hintText: '例：ご飯は小盛り、ドレッシングなし',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            if (_busy) ...[
              const ModalBarrier(dismissible: false, color: Colors.black38),
              Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(_busyLabel),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChainInput {
  const _ChainInput(this.store, this.menu, this.withPhoto);

  final String store;
  final String menu;
  final bool withPhoto;
}

class _ChainDialog extends StatefulWidget {
  const _ChainDialog();

  @override
  State<_ChainDialog> createState() => _ChainDialogState();
}

class _ChainDialogState extends State<_ChainDialog> {
  final _store = TextEditingController();
  final _menu = TextEditingController();
  bool _withPhoto = false;

  @override
  void dispose() {
    _store.dispose();
    _menu.dispose();
    super.dispose();
  }

  bool get _valid => _store.text.trim().isNotEmpty && _menu.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('チェーン店メニュー'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _store,
            decoration: const InputDecoration(labelText: '店名', hintText: '例：吉野家'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _menu,
            decoration: const InputDecoration(labelText: 'メニュー名（サイズも）', hintText: '例：牛丼 並盛'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _withPhoto,
            onChanged: (v) => setState(() => _withPhoto = v ?? false),
            title: const Text('写真も添える'),
            subtitle: const Text('サイズやトッピングの判別に使います'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.pop(context, _ChainInput(_store.text.trim(), _menu.text.trim(), _withPhoto))
              : null,
          child: const Text('検索'),
        ),
      ],
    );
  }
}
