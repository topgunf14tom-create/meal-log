import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../services/health_service.dart';

/// ヘルスコネクトの権限をリクエストし、許可されたら連携をオンにして同期する。
/// 結果をスナックバーで表示し、連携できたら true
Future<bool> connectHealth(BuildContext context) async {
  final s = AppServices.I;
  final messenger = ScaffoldMessenger.of(context);
  void snack(String m) => messenger.showSnackBar(SnackBar(content: Text(m)));

  final status = await s.health.status();
  if (status == HealthStatus.unavailable) {
    snack('この端末ではヘルスコネクトを使えません');
    return false;
  }
  if (status == HealthStatus.updateRequired) {
    snack('ヘルスコネクトの更新が必要です。Playストアで更新してください');
    return false;
  }
  Set<String> granted;
  try {
    granted = await s.health.request();
  } catch (e) {
    snack('権限画面を開けませんでした：$e');
    return false;
  }
  if (granted.isEmpty) {
    snack('権限が許可されませんでした');
    return false;
  }
  await s.settings.set('health_enabled', 'true');
  final missing = HealthService.allKeys.where((k) => !granted.contains(k)).map((k) => HealthService.keyLabels[k]);
  final msg = await s.activity.sync(force: true);
  snack([
    if (missing.isNotEmpty) '未許可：${missing.join('・')}',
    if (msg != null) msg,
  ].join(' / ').ifEmpty('連携しました'));
  return true;
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
