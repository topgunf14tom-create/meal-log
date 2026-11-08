import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 共有用に画像にする範囲。背景色をつけて透明にならないようにする
class ShareFrame extends StatelessWidget {
  const ShareFrame({super.key, required this.captureKey, required this.child});

  final GlobalKey captureKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        key: captureKey,
        child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor, child: child),
      );
}

/// [captureKey] の範囲を PNG にして、テキストと一緒に共有（LINE・X・Instagram など）
Future<void> shareCapture(
  BuildContext context,
  GlobalKey captureKey, {
  required String text,
  required String fileName,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final boundary = captureKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) throw StateError('画面の準備ができていません');
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) throw StateError('画像を作れませんでした');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName.png');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    await SharePlus.instance.share(ShareParams(
      text: text,
      files: [XFile(file.path, mimeType: 'image/png')],
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('共有できませんでした：$e')));
  }
}

/// AppBar に置く共有ボタン
class ShareButton extends StatelessWidget {
  const ShareButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) =>
      IconButton(tooltip: '共有', icon: const Icon(Icons.share_outlined), onPressed: onPressed);
}
