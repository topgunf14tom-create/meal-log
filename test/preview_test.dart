import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_log/core/meal_type.dart';
import 'package:meal_log/core/theme.dart';
import 'package:meal_log/widgets/macro_widgets.dart';
import 'package:meal_log/widgets/scale_display.dart';

/// デザイン確認用のプレビュー画像（build/preview/*.png）。CI が成果物として保存する
Future<void> _loadFont() async {
  final loader = FontLoader('ZenKaku');
  for (final w in ['Regular', 'Medium', 'Bold']) {
    final bytes = File('assets/fonts/ZenKakuGothicNew-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
  final root = Platform.environment['FLUTTER_ROOT'];
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (root != null && icons.existsSync()) {
    final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
    await l.load();
  }
}

Widget _home(Map<MealType, double> byType, double target) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Scaffold(
        appBar: AppBar(
          leading: const Icon(Icons.chevron_left),
          titleSpacing: 0,
          title: const Text('11月11日（水）  今日'),
          actions: const [Icon(Icons.chevron_right), SizedBox(width: 12), Icon(Icons.ios_share), SizedBox(width: 12), Icon(Icons.settings_outlined), SizedBox(width: 12)],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {},
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('記録する'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            ScaleDisplay(byType: byType, target: target, baseTarget: 2200, burn: target - 2200),
            const SizedBox(height: 14),
            const MacroBar(label: 'たんぱく質', value: 82, target: 110, color: MacroColors.protein),
            const SizedBox(height: 12),
            const MacroBar(label: '脂質', value: 66, target: 61, color: MacroColors.fat),
            const SizedBox(height: 12),
            const MacroBar(label: '炭水化物', value: 190, target: 302, color: MacroColors.carbs),
            const SizedBox(height: 8),
            const Text('エネルギー比 P22 F39 C51（目標 20/25/55）', style: TextStyle(fontSize: 12, color: AppColors.sub)),
            const SizedBox(height: 16),
            for (final (t, name, k) in [
              ('朝食', '鮭おにぎり、味噌汁', '412'),
              ('昼食', 'すき家 牛丼 並盛', '733'),
            ]) ...[
              Container(
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.text, width: 1.5))),
                padding: const EdgeInsets.fromLTRB(2, 10, 2, 4),
                child: Row(children: [
                  Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('$k kcal'),
                ]),
              ),
              Container(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(name),
              ),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );

Future<void> _shot(WidgetTester tester, Widget w, String name) async {
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(key: key, child: w));
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final f = File('build/preview/$name.png');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('ホームのプレビュー', (tester) async {
    await tester.runAsync(_loadFont);
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _shot(tester, _home({MealType.breakfast: 412, MealType.lunch: 733, MealType.snack: 180}, 2200), 'home_remaining');
    await _shot(tester, _home({MealType.breakfast: 520, MealType.lunch: 980, MealType.dinner: 1050}, 2450), 'home_over');
    expect(find.byType(ScaleDisplay), findsOneWidget);
  });
}
