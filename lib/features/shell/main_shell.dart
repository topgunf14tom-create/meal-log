import 'package:flutter/material.dart';

import '../history/exercise_history_screen.dart';
import '../home/home_screen.dart';
import '../inbody/inbody_history_screen.dart';
import '../report/report_screen.dart';
import '../weight/weight_screen.dart';

/// 画面下のタブで ホーム・体重・体組成・運動・レポート を切り替える。
/// ホームは表示中の日付を保つため作り直さない。ほかのタブは開くたびに作り直して最新を読む。
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  int _visit = 0;

  static const _tabs = [
    (icon: Icons.restaurant_outlined, selected: Icons.restaurant, label: 'ホーム'),
    (icon: Icons.monitor_weight_outlined, selected: Icons.monitor_weight, label: '体重'),
    (icon: Icons.accessibility_new_outlined, selected: Icons.accessibility_new, label: '体組成'),
    (icon: Icons.directions_run_outlined, selected: Icons.directions_run, label: '運動'),
    (icon: Icons.insights_outlined, selected: Icons.insights, label: 'レポート'),
  ];

  void _select(int i) {
    if (i == _index && i != 0) return;
    setState(() {
      _index = i;
      _visit++;
    });
    if (i == 0) homeReload.value++;
  }

  Widget _page(int i) {
    final key = ValueKey('tab$i-$_visit');
    switch (i) {
      case 1:
        return WeightScreen(key: key);
      case 2:
        return InBodyHistoryScreen(key: key);
      case 3:
        return ExerciseHistoryScreen(key: key);
      default:
        return ReportScreen(key: key);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: Scaffold(
        body: Stack(
          children: [
            Offstage(offstage: _index != 0, child: const HomeScreen()),
            if (_index != 0) _page(_index),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: [
            for (final t in _tabs)
              NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selected), label: t.label),
          ],
        ),
      ),
    );
  }
}
