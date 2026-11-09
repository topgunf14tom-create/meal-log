import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/dates.dart';
import '../../data/entities.dart';
import '../../widgets/goal_form.dart';
import '../shell/main_shell.dart';
import '../settings/api_key_widgets.dart';

/// 初回起動の案内（APIキー未設定のときだけ表示）
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.fromSettings = false});

  final bool fromSettings;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pc = PageController();
  late final Future<Goal> _goalFuture = AppServices.I.db.goalOn(ymd(DateTime.now()));
  int _page = 0;
  static const _pageCount = 4;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _pageCount - 1) {
      _pc.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    await AppServices.I.settings.set('onboarding_done', true);
    if (!mounted) return;
    if (widget.fromSettings) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
    }
  }

  Widget _pageBody(List<Widget> children) => ListView(padding: const EdgeInsets.all(24), children: children);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pages = [
      _pageBody([
        const SizedBox(height: 24),
        Icon(Icons.restaurant, size: 72, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 24),
        Text('食事記録へようこそ', style: t.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        const Text(
          '・食事の写真を撮るだけで、料理名・カロリー・PFCを推定して記録します\n'
          '・チェーン店のメニューは公式サイトの栄養成分を検索します\n'
          '・目標カロリー、PFCバランス、体重の推移を確認できます\n'
          '・記録データはこの端末の中だけに保存されます',
        ),
        const SizedBox(height: 16),
        Text('写真解析にはあなた自身の Claude APIキーが必要です。次の画面で取得方法を案内します。', style: t.bodySmall),
      ]),
      _pageBody([const ApiKeyGuide()]),
      _pageBody([
        Text('APIキーを入力', style: t.titleMedium),
        const SizedBox(height: 8),
        const Text('コピーしたキーを貼り付けて「接続テストして保存」を押してください。'),
        const SizedBox(height: 16),
        ApiKeyForm(onSaved: _next),
        const SizedBox(height: 24),
        Text('キーがなくても手入力での記録と体重記録は使えます。あとから設定画面で登録できます。', style: t.bodySmall),
      ]),
      _pageBody([
        Text('目標を設定', style: t.titleMedium),
        const SizedBox(height: 16),
        FutureBuilder<Goal>(
          future: _goalFuture,
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            return GoalForm(
              initial: snap.data!,
              buttonLabel: '保存して始める',
              onSave: (g) async {
                await AppServices.I.db.saveGoal(g);
                await _finish();
              },
            );
          },
        ),
      ]),
    ];

    return Scaffold(
      appBar: widget.fromSettings ? AppBar(title: const Text('初回案内')) : null,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pc,
                onPageChanged: (i) => setState(() => _page = i),
                children: pages,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  for (var i = 0; i < _pageCount; i++)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _page
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  const Spacer(),
                  if (_page == 2) TextButton(onPressed: _next, child: const Text('あとで設定')),
                  if (_page == 3) TextButton(onPressed: _finish, child: const Text('スキップ')),
                  if (_page < 2) FilledButton(onPressed: _next, child: const Text('次へ')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
