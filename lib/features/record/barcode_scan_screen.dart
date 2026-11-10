import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app_services.dart';
import '../../core/food_db.dart';
import '../../core/label_text.dart';

class ScannedCode {
  ScannedCode(this.jan, [this.count = 1]);

  final String jan;
  int count;
}

/// JAN バーコードの連続スキャン（端末内で読み取り、個人DBと照合。LLMは使わない）。
/// 読み取った商品を一覧にためて、まとめて1食として返す
class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key});

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final _codes = <ScannedCode>[];
  final _lastSeen = <String, DateTime>{};
  FoodDb? _db;

  @override
  void initState() {
    super.initState();
    AppServices.I.foods.ready.then((db) {
      if (mounted) setState(() => _db = db);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final code = b.rawValue?.trim() ?? '';
      if (!isValidJan(code)) continue;
      // 同じ商品をかざし続けたときの重複を防ぐ（2.5秒以内は無視）
      final now = DateTime.now();
      final last = _lastSeen[code];
      if (last != null && now.difference(last) < const Duration(milliseconds: 2500)) continue;
      _lastSeen[code] = now;
      setState(() {
        final i = _codes.indexWhere((c) => c.jan == code);
        if (i >= 0) {
          _codes[i].count++;
        } else {
          _codes.add(ScannedCode(code));
        }
      });
      final name = _db?.byJan(code)?.name ?? '未登録の商品';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('読み取り：$name'), duration: const Duration(milliseconds: 1000)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('バーコードを続けて読み取る'),
        actions: [
          IconButton(icon: const Icon(Icons.flashlight_on_outlined), onPressed: () => _controller.toggleTorch()),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 260,
            child: MobileScanner(controller: _controller, onDetect: _onDetect),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '商品のバーコードを順にかざしてください。登録済みはそのまま記録、未登録は次に栄養成分表示を撮って登録します。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (var i = 0; i < _codes.length; i++)
                  ListTile(
                    leading: Icon(_db?.byJan(_codes[i].jan) != null ? Icons.check_circle_outline : Icons.help_outline),
                    title: Text(_db?.byJan(_codes[i].jan)?.displayName ?? '未登録の商品'),
                    subtitle: Text('JAN ${_codes[i].jan}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => setState(() {
                            if (_codes[i].count > 1) {
                              _codes[i].count--;
                            } else {
                              _codes.removeAt(i);
                            }
                          }),
                        ),
                        Text('${_codes[i].count}'),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => setState(() => _codes[i].count++),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _codes.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(List<ScannedCode>.of(_codes)),
                  child: Text('${_codes.fold<int>(0, (a, c) => a + c.count)}点をまとめて記録'),
                ),
              ),
            ),
    );
  }
}
