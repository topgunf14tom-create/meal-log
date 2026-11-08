import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../services/strava_import.dart';

/// Strava の書き出しを選んで取り込む。取り込んだ件数を返す（中止・失敗は null）
Future<int?> runStravaImport(BuildContext context) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Strava の記録を取り込む'),
      content: const SingleChildScrollView(
        child: Text(
          '過去の記録（ルート・心拍・標高を含む）を取り込めます。\n\n'
          '1. PC のブラウザで strava.com にログイン\n'
          '2. 設定 →「マイアカウント」→「アカウントのダウンロードまたは削除」→「リクエスト」\n'
          '3. メールで届く zip をスマホに保存\n'
          '4. 下の「ファイルを選ぶ」でその zip を選ぶ\n\n'
          'activities.csv や、1件分の GPX・TCX・FIT ファイルも選べます。'
          '同じ記録をもう一度取り込むと上書きされます。取り込みは端末の中だけで行います。',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('ファイルを選ぶ')),
      ],
    ),
  );
  if (go != true || !context.mounted) return null;

  final messenger = ScaffoldMessenger.of(context);
  String? path;
  try {
    path = await pickImportFile();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('ファイルを開けませんでした：$e')));
    return null;
  }
  if (path == null || !context.mounted) return null;

  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('取り込み中…\n件数が多いと数分かかります')),
          ],
        ),
      ),
    ),
  );
  try {
    final r = await importStravaFile(path);
    final n = await AppServices.I.db.saveStravaActivities(r.activities);
    nav.pop();
    final extra = [
      if (r.skipped > 0) '${r.skipped}件は日時が読めず取り込めませんでした',
      if (r.errors.isNotEmpty) '読めなかったファイル：${r.errors.first}',
    ].join('\n');
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(n == 0 ? '取り込める記録がありませんでした' : '$n件を取り込みました'),
          content: extra.isEmpty ? null : Text(extra),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
    }
    return n;
  } catch (e) {
    nav.pop();
    messenger.showSnackBar(SnackBar(content: Text('取り込めませんでした：$e')));
    return null;
  }
}
