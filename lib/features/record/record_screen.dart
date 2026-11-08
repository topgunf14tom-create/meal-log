import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app_services.dart';
import '../../core/dates.dart';
import '../../core/meal_type.dart';
import '../../data/entities.dart';
import '../../services/nutrition_service.dart';
import '../result_edit/result_edit_screen.dart';
import '../settings/api_key_widgets.dart';
import 'alcohol_screen.dart';

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

  Future<void> _photo() async {
    if (!await _ensureKey()) return;
    final bytes = await _pickPhoto();
    if (bytes == null) return;
    await _analyze('写真を解析中…', () => s.nutrition.analyzePhoto(bytes, hint: _hint.text), bytes);
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

    final manual = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('解析できませんでした'),
        content: Text('$error'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('閉じる')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('手入力する')),
        ],
      ),
    );
    if (manual == true) {
      await _openEditor(items: [MealItem.manual], photo: photo, model: 'manual');
    }
  }

  Future<void> _openEditor({
    required List<MealItem> items,
    Uint8List? photo,
    String? model,
    String? note,
  }) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ResultEditScreen(
        date: ymd(widget.date),
        mealType: _type,
        items: items,
        photoBytes: photo,
        modelUsed: model,
        note: note,
        hint: _hint.text,
      ),
    ));
    if (saved == true && mounted) Navigator.of(context).pop(true);
  }

  Widget _action(IconData icon, String title, String subtitle, VoidCallback onTap) => Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Icon(icon, size: 32),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
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
                _action(Icons.photo_camera, '写真で解析', '撮影した料理のカロリー・PFCを推定（Haiku）', _photo),
                _action(Icons.storefront, 'チェーン店メニュー', '公式サイトの栄養成分を検索（Sonnet＋Web検索）', _chain),
                _action(Icons.sports_bar, 'お酒', 'ビール・ハイボール・ワインなどを選んで記録（APIキー不要）', _alcohol),
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
