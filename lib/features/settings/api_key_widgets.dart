import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_services.dart';
import '../../core/theme.dart';
import '../../core/links.dart';
import '../../services/claude_client.dart';

/// APIキーの取得手順
class ApiKeyGuide extends StatelessWidget {
  const ApiKeyGuide({super.key});

  Widget _step(int n, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(radius: 11, child: Text('$n', style: const TextStyle(fontSize: 12))),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('APIキーの取得手順', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _step(1, 'platform.claude.com でアカウントを作成'),
        _step(2, 'Billing でクレジットを購入（少額でOK）'),
        _step(3, 'Limits で月の利用上限を設定（おすすめ）'),
        _step(4, 'API Keys でキーを発行してコピー（表示は一度だけ）'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => openUrl(consoleUrl),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Consoleを開く'),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '料金の目安：1日3食の記録で月100〜300円程度。\n'
              '料金はAPIキーを発行した本人のClaudeアカウントに請求されます。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }
}

/// APIキー入力＋接続テスト。成功したら保存して onSaved を呼ぶ
class ApiKeyForm extends StatefulWidget {
  const ApiKeyForm({super.key, required this.onSaved});

  final VoidCallback onSaved;

  @override
  State<ApiKeyForm> createState() => _ApiKeyFormState();
}

class _ApiKeyFormState extends State<ApiKeyForm> {
  final _c = TextEditingController();
  bool _obscure = true;
  bool _testing = false;
  bool _ok = false;
  String? _message;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text?.trim();
    if (t != null && t.isNotEmpty) setState(() => _c.text = t);
  }

  Future<void> _test() async {
    final key = _c.text.trim();
    if (!key.startsWith('sk-ant-')) {
      setState(() {
        _ok = false;
        _message = '「sk-ant-」で始まるキーを貼り付けてください';
      });
      return;
    }
    setState(() {
      _testing = true;
      _message = null;
    });
    try {
      await AppServices.I.nutrition.testKey(key);
      await AppServices.I.keys.write(key);
      if (!mounted) return;
      setState(() {
        _ok = true;
        _message = '接続OK。キーを保存しました';
      });
      widget.onSaved();
    } on ClaudeException catch (e) {
      if (mounted) {
        setState(() {
          _ok = false;
          _message = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _ok = false;
          _message = '接続できませんでした: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _c,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Anthropic APIキー',
            hintText: 'sk-ant-...',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(onPressed: _paste, icon: const Icon(Icons.content_paste), label: const Text('貼り付け')),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _testing ? null : _test,
                icon: _testing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_tethering),
                label: const Text('接続テストして保存'),
              ),
            ),
          ],
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_ok ? Icons.check_circle : Icons.error, color: _ok ? AppColors.success : scheme.error),
              const SizedBox(width: 8),
              Expanded(child: Text(_message!)),
            ],
          ),
        ],
      ],
    );
  }
}

/// 設定画面・記録画面から開くキー設定画面
class ApiKeyScreen extends StatelessWidget {
  const ApiKeyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('APIキーの設定')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ApiKeyGuide(),
          const SizedBox(height: 24),
          ApiKeyForm(onSaved: () => Navigator.of(context).pop(true)),
        ],
      ),
    );
  }
}
