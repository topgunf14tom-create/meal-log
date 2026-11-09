import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/meal_type.dart';
import '../../core/reminders.dart';

String _dateTime(DateTime d) =>
    '${d.month}/${d.day} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

/// 自動バックアップ（利用者が選んだファイルに毎日上書き保存）
class BackupSection extends StatefulWidget {
  const BackupSection({super.key});

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  bool _busy = false;

  AppServices get s => AppServices.I;

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      _snack('できませんでした：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose() => _run(() async {
        final ok = await s.backup.chooseLocation();
        if (ok) _snack(s.backup.onGoogleDrive ? 'Google ドライブに保存しました' : '保存しました');
      });

  Future<void> _restore() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('バックアップから戻す'),
        content: const Text(
          'バックアップのファイル（meal-log-backup.json など）を選ぶと、今のデータはすべて置き換わります。'
          '写真と Strava の取り込みは含まれません。戻したあとはアプリを一度終了して開き直してください。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('ファイルを選ぶ')),
        ],
      ),
    );
    if (go != true) return;
    await _run(() async {
      final ok = await s.backup.restoreFromFile();
      if (ok) _snack('戻しました。アプリを開き直してください');
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = s.backup;
    final small = Theme.of(context).textTheme.bodySmall;
    final last = b.lastBackup;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!b.enabled) ...[
              const Text('保存先のファイルを選ぶと、アプリを開いたときに1日1回、自動で上書き保存します。'
                  '保存先の画面で「ドライブ」を選べば Google ドライブに保存され、機種変更や入れ直しのときに戻せます。'),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy ? null : _choose,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('保存先を選んでオンにする'),
              ),
            ] else ...[
              Text('保存先：${b.name ?? 'ファイル'}${b.onGoogleDrive ? '（Google ドライブ）' : ''}'),
              Text(last == null ? 'まだ保存していません' : '最後の保存：${_dateTime(last)}', style: small),
              if (b.lastError != null)
                Text('前回の保存に失敗：${b.lastError}', style: small?.copyWith(color: Theme.of(context).colorScheme.error)),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => _run(() async {
                          await b.backupNow();
                          _snack('保存しました');
                        }),
                    child: const Text('今すぐ保存'),
                  ),
                  TextButton(onPressed: _busy ? null : _choose, child: const Text('保存先を変える')),
                  TextButton(
                    onPressed: _busy ? null : () => _run(() async {
                          await b.turnOff();
                          _snack('自動バックアップをオフにしました');
                        }),
                    child: const Text('オフにする'),
                  ),
                ],
              ),
            ],
            const Divider(),
            TextButton.icon(
              onPressed: _busy ? null : _restore,
              icon: const Icon(Icons.restore),
              label: const Text('バックアップから戻す'),
            ),
            Text('写真と Strava の取り込みはバックアップに含まれません（Strava は zip から取り込み直せます）', style: small),
          ],
        ),
      ),
    );
  }
}

/// 記録忘れの通知
class ReminderSection extends StatefulWidget {
  const ReminderSection({super.key});

  @override
  State<ReminderSection> createState() => _ReminderSectionState();
}

class _ReminderSectionState extends State<ReminderSection> {
  AppServices get s => AppServices.I;

  Future<void> _toggle(bool on) async {
    if (on) {
      final ok = await s.reminders.enable();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('通知が許可されていません。Android の設定 → アプリ → 食事記録 → 通知 から許可してください')),
        );
      }
    } else {
      await s.reminders.disable();
    }
    if (mounted) setState(() {});
  }

  Future<void> _pick(MealType t, int? current) async {
    final init = current ?? defaultReminderMinutes[t]!;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: init ~/ 60, minute: init % 60),
    );
    if (picked == null) return;
    await s.reminders.setTime(t, picked.hour * 60 + picked.minute);
    await s.reminders.reschedule();
    if (mounted) setState(() {});
  }

  Future<void> _off(MealType t) async {
    await s.reminders.setTime(t, null);
    await s.reminders.reschedule();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final r = s.reminders;
    final minutes = r.minutes;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('記録忘れを通知'),
            subtitle: const Text('その時刻までに記録が無いときだけ通知します'),
            value: r.enabled,
            onChanged: _toggle,
          ),
          if (r.enabled)
            for (final t in reminderTypes)
              ListTile(
                dense: true,
                title: Text(t.label),
                subtitle: Text(minutes[t] == null ? '通知しない' : formatHm(minutes[t]!)),
                onTap: () => _pick(t, minutes[t]),
                trailing: minutes[t] == null
                    ? TextButton(onPressed: () => _pick(t, null), child: const Text('設定'))
                    : IconButton(
                        tooltip: '通知しない',
                        icon: const Icon(Icons.notifications_off_outlined),
                        onPressed: () => _off(t),
                      ),
              ),
          if (r.enabled)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('通知は7日先まで予約し、アプリを開くたびに更新します。数分ずれることがあります。',
                  style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

/// ホーム画面ウィジェットの案内
class WidgetHelpCard extends StatelessWidget {
  const WidgetHelpCard({super.key});

  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'ホーム画面の空いている所を長押し →「ウィジェット」→「食事記録」を追加すると、'
            '今日の残りカロリー・摂取・歩数が表示されます。値はアプリを開いたときに更新されます。',
          ),
        ),
      );
}
