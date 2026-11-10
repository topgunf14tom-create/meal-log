import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_services.dart';
import '../../core/dates.dart';
import '../../core/links.dart';
import '../../core/models.dart';
import '../../data/entities.dart';
import '../../services/health_service.dart';
import '../../widgets/goal_form.dart';
import '../onboarding/onboarding_screen.dart';
import 'api_key_widgets.dart';
import 'backup_reminder_section.dart';
import 'food_db_section.dart';
import 'health_connect.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppServices get s => AppServices.I;

  Goal? _goal;
  String? _key;
  UsageSummary _usage = const UsageSummary();
  int _cacheCount = 0;
  HealthStatus? _healthStatus;
  Set<String> _granted = {};
  String _heightInfo = '';
  late final _height = TextEditingController(text: s.settings.heightCm?.toStringAsFixed(1) ?? '');

  late final _photoModel = TextEditingController(text: s.settings.photoModel);
  late final _chainModel = TextEditingController(text: s.settings.chainModel);
  late final _reModel = TextEditingController(text: s.settings.reanalyzeModel);
  late int _maxSide = s.settings.maxSide;
  late double _quality = s.settings.jpegQuality.toDouble();
  late final _fx = TextEditingController(text: s.settings.fxRate.toString());
  late final _hIn = TextEditingController(text: s.settings.prices.haikuIn.toString());
  late final _hOut = TextEditingController(text: s.settings.prices.haikuOut.toString());
  late final _sIn = TextEditingController(text: s.settings.prices.sonnetIn.toString());
  late final _sOut = TextEditingController(text: s.settings.prices.sonnetOut.toString());
  late final _search = TextEditingController(text: s.settings.prices.searchUsd.toString());

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_photoModel, _chainModel, _reModel, _fx, _hIn, _hOut, _sIn, _sOut, _search, _height]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final goal = await s.db.goalOn(ymd(now));
    final key = await s.keys.read();
    final usage = await s.db.usageForMonth(ym(now));
    final cache = await s.db.chainCacheCount();
    final hs = await s.health.status();
    final granted = await s.health.granted();
    final (h, src) = await s.activity.heightSource();
    if (!mounted) return;
    setState(() {
      _healthStatus = hs;
      _granted = granted;
      _heightInfo = '計算に使う身長：${h.toStringAsFixed(1)} cm（$src）';
      _goal = goal;
      _key = key;
      _usage = usage;
      _cacheCount = cache;
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _masked(String k) => k.length <= 12 ? '••••' : '${k.substring(0, 7)}••••${k.substring(k.length - 4)}';

  Future<void> _saveAdvanced() async {
    final st = s.settings;
    await st.set('photo_model', _photoModel.text.trim());
    await st.set('chain_model', _chainModel.text.trim());
    await st.set('reanalyze_model', _reModel.text.trim());
    await st.set('max_side', _maxSide);
    await st.set('jpeg_quality', _quality.round());
    final pairs = <(String, TextEditingController)>[
      ('fx_rate', _fx),
      ('price_haiku_in', _hIn),
      ('price_haiku_out', _hOut),
      ('price_sonnet_in', _sIn),
      ('price_sonnet_out', _sOut),
      ('price_search', _search),
    ];
    for (final (key, c) in pairs) {
      if (double.tryParse(c.text.trim()) != null) await st.set(key, c.text.trim());
    }
    _snack('設定を保存しました');
  }

  Future<void> _saveHeight() async {
    final t = _height.text.trim();
    final v = double.tryParse(t);
    if (t.isNotEmpty && (v == null || v < 80 || v > 250)) {
      _snack('身長を正しく入力してください（cm）');
      return;
    }
    await s.settings.set('height_cm', t);
    if (mounted) FocusScope.of(context).unfocus();
    await _load();
    await s.activity.sync(force: true);
    _snack(t.isEmpty ? '身長は自動取得の値を使います' : '身長を保存しました');
  }

  Widget _healthSection() {
    final small = Theme.of(context).textTheme.bodySmall;
    final st = _healthStatus;
    if (st == null) return const SizedBox.shrink();
    if (st != HealthStatus.available) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.health_and_safety_outlined),
          title: Text(st == HealthStatus.updateRequired ? 'ヘルスコネクトの更新が必要です' : 'この端末では使えません'),
          subtitle: const Text('Android のヘルスコネクトが必要です'),
        ),
      );
    }
    final on = s.settings.healthEnabled;
    final missing = HealthService.allKeys.where((k) => !_granted.contains(k)).toList();
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.health_and_safety_outlined),
            title: const Text('自動で取り込む'),
            subtitle: Text(on
                ? (missing.isEmpty
                    ? 'アプリを開いたときに体重・歩数・運動を取り込みます'
                    : '未許可：${missing.map((k) => HealthService.keyLabels[k]).join('・')}')
                : 'InBody・Strava などがヘルスコネクトに書いたデータを読み取ります'),
            value: on && _granted.isNotEmpty,
            onChanged: (v) async {
              if (v) {
                await connectHealth(context);
              } else {
                await s.settings.set('health_enabled', 'false');
              }
              await _load();
            },
          ),
          SwitchListTile(
            title: const Text('消費カロリーを目標に上乗せ'),
            subtitle: const Text('歩数と運動の分だけ、その日の目標カロリーを増やします'),
            value: s.settings.addBurnToGoal,
            onChanged: (v) async {
              await s.settings.set('add_burn_to_goal', v ? 'true' : 'false');
              setState(() {});
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _height,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '身長（空欄なら自動）',
                      suffixText: 'cm',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(onPressed: _saveHeight, child: const Text('保存')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('$_heightInfo\n歩幅＝身長×0.45、歩行カロリー＝体重×距離×0.5。運動中の歩数は除き、運動は活動カロリー（無ければ推定）で計算',
                style: small),
          ),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => s.health.openSettings(), child: const Text('ヘルスコネクトの設定')),
              if (on)
                TextButton(
                  onPressed: () async {
                    final msg = await s.activity.sync(force: true);
                    if (msg != null) _snack(msg);
                  },
                  child: const Text('今すぐ同期'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _resetModels() {
    setState(() {
      _photoModel.text = ModelIds.photoDefault;
      _chainModel.text = ModelIds.chainDefault;
      _reModel.text = ModelIds.reanalyzeDefault;
    });
  }

  Future<void> _deleteKey() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('APIキーを削除しますか？'),
        content: const Text('この端末からキーを消します。Console側のキーは無効化されないので、不要ならConsoleでも削除してください。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('削除')),
        ],
      ),
    );
    if (ok != true) return;
    await s.keys.delete();
    await _load();
  }

  Future<void> _export() async {
    final data = await s.db.exportAll();
    await Clipboard.setData(ClipboardData(text: jsonEncode(data)));
    _snack('バックアップ（JSON）をクリップボードにコピーしました。メモアプリ等に貼り付けて保管してください');
  }

  Future<void> _import() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('バックアップから復元'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('エクスポートしたJSONを貼り付けてください。今のデータはすべて置き換わります。'),
            const SizedBox(height: 8),
            TextField(controller: c, maxLines: 6, decoration: const InputDecoration(border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('復元')),
        ],
      ),
    );
    final text = c.text;
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    if (ok != true) return;
    try {
      final data = jsonDecode(text);
      if (data is! Map) throw const FormatException('形式が正しくありません');
      await s.db.importAll(data.cast<String, dynamic>());
      _snack('復元しました（設定は再起動後に反映されます）');
      await _load();
    } catch (e) {
      _snack('復元できませんでした: $e');
    }
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _text(TextEditingController c, String label, {bool number = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final fx = double.tryParse(_fx.text) ?? 150;
    final small = Theme.of(context).textTheme.bodySmall;
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _section('目標'),
          if (_goal == null)
            const Center(child: CircularProgressIndicator())
          else
            GoalForm(
              key: ValueKey(_goal!.startDate),
              initial: _goal!,
              onSave: (g) async {
                await s.db.saveGoal(g);
                _snack('目標を保存しました（今日から適用）');
              },
            ),

          _section('記録'),
          const RecordPrefsSection(),

          _section('食品データベース'),
          const FoodDbSection(),

          _section('ヘルスコネクト'),
          _healthSection(),

          _section('自動バックアップ'),
          const BackupSection(),

          _section('記録忘れの通知'),
          const ReminderSection(),

          _section('ホーム画面ウィジェット'),
          const WidgetHelpCard(),

          _section('Claude APIキー'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(_key == null ? Icons.key_off : Icons.key),
                  title: Text(_key == null ? '未設定' : _masked(_key!)),
                  subtitle: Text(_key == null ? '写真解析・チェーン店検索には設定が必要です' : 'この端末の安全な領域に保存されています'),
                ),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  children: [
                    if (_key != null) TextButton(onPressed: _deleteKey, child: const Text('削除')),
                    TextButton(
                      onPressed: () async {
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ApiKeyScreen()));
                        await _load();
                      },
                      child: Text(_key == null ? '設定する' : '変更'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const OnboardingScreen(fromSettings: true)));
                        await _load();
                      },
                      child: const Text('初回案内を表示'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          _section('今月のAPI利用量'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('約 ${(_usage.usd * fx).round()} 円（\$${_usage.usd.toStringAsFixed(3)}）',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text('リクエスト ${_usage.requests}回 / Web検索 ${_usage.webSearches}回', style: small),
                  Text('入力 ${_usage.inputTokens} / 出力 ${_usage.outputTokens} トークン', style: small),
                  const SizedBox(height: 4),
                  Text('※アプリ内の概算です。正確な請求額はConsoleで確認してください', style: small),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: () => openUrl(consoleUrl), child: const Text('Consoleを開く')),
                  ),
                ],
              ),
            ),
          ),

          _section('モデル'),
          _text(_photoModel, '写真判定・ラベル転記（Haiku 推奨）'),
          _text(_chainModel, 'チェーン店検索'),
          _text(_reModel, '再判定（手動で選んだときだけ）'),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: _resetModels, child: const Text('初期値に戻す')),
          ),

          _section('画像圧縮'),
          Row(
            children: [
              const Text('長辺'),
              const SizedBox(width: 16),
              DropdownButton<int>(
                value: _maxSide,
                items: const [
                  DropdownMenuItem(value: 768, child: Text('768 px（安い）')),
                  DropdownMenuItem(value: 1024, child: Text('1024 px（標準）')),
                  DropdownMenuItem(value: 1280, child: Text('1280 px（高精細）')),
                ],
                onChanged: (v) => setState(() => _maxSide = v ?? 1024),
              ),
            ],
          ),
          Row(
            children: [
              Text('JPEG品質 ${_quality.round()}'),
              Expanded(
                child: Slider(
                  value: _quality,
                  min: 60,
                  max: 90,
                  divisions: 6,
                  label: _quality.round().toString(),
                  onChanged: (v) => setState(() => _quality = v),
                ),
              ),
            ],
          ),

          _section('料金単価（概算表示用）'),
          Text('USD / 100万トークン。料金改定があったらここを直してください', style: small),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _text(_hIn, 'Haiku 入力', number: true)),
            const SizedBox(width: 8),
            Expanded(child: _text(_hOut, 'Haiku 出力', number: true)),
          ]),
          Row(children: [
            Expanded(child: _text(_sIn, 'Sonnet 入力', number: true)),
            const SizedBox(width: 8),
            Expanded(child: _text(_sOut, 'Sonnet 出力', number: true)),
          ]),
          Row(children: [
            Expanded(child: _text(_search, 'Web検索 1回 (USD)', number: true)),
            const SizedBox(width: 8),
            Expanded(child: _text(_fx, '為替 (円/USD)', number: true)),
          ]),
          const SizedBox(height: 8),
          FilledButton(onPressed: _saveAdvanced, child: const Text('モデル・圧縮・単価を保存')),

          _section('データ'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.upload),
                  title: const Text('エクスポート'),
                  subtitle: const Text('全データをJSONでクリップボードにコピー（手動）'),
                  onTap: _export,
                ),
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('インポート'),
                  subtitle: const Text('JSONを貼り付けて復元（写真は含まれません）'),
                  onTap: _import,
                ),
                ListTile(
                  leading: const Icon(Icons.storefront),
                  title: Text('チェーン店キャッシュ $_cacheCount 件'),
                  subtitle: const Text('タップで削除（次回から再検索）'),
                  onTap: () async {
                    await s.db.clearChainCache();
                    await _load();
                    _snack('キャッシュを削除しました');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
