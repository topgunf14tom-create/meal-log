import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/inbody.dart';
import 'inbody_result_screen.dart';

/// InBody の結果用紙の QR を読み取る（カメラ・写真・貼り付け）
class InBodyScanScreen extends StatefulWidget {
  const InBodyScanScreen({super.key});

  @override
  State<InBodyScanScreen> createState() => _InBodyScanScreenState();
}

class _InBodyScanScreenState extends State<InBodyScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _handling = false;
  String? _lastRejected;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final text = b.rawValue;
      if (text != null && text.isNotEmpty) {
        _handle(text);
        return;
      }
    }
  }

  Future<void> _handle(String text, {bool fromCamera = true}) async {
    if (_handling) return;
    // 同じ読み取り失敗を何度も表示しない
    if (fromCamera && text == _lastRejected) return;
    _handling = true;
    try {
      final result = parseInBodyQr(text);
      await _controller.stop();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => InBodyResultScreen(result: result)),
      );
    } on InBodyFormatException catch (e) {
      _lastRejected = text;
      _showError(e.message);
    } finally {
      _handling = false;
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _fromPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final capture = await _controller.analyzeImage(picked.path);
    final text = capture?.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (text == null) {
      _showError('写真から QR コードが見つかりませんでした。QR が大きく写った写真を選んでください');
      return;
    }
    await _handle(text, fromCamera: false);
  }

  Future<void> _fromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _showError('クリップボードが空です');
      return;
    }
    await _handle(text, fromCamera: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('InBody の QR を読み取る'),
        actions: [
          IconButton(
            tooltip: 'ライト',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // 読み取り枠
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '結果用紙の右下の QR コードを枠に合わせてください',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, shadows: [Shadow(blurRadius: 4)]),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _fromPhoto,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('写真から'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _fromClipboard,
                          icon: const Icon(Icons.content_paste),
                          label: const Text('貼り付け'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
