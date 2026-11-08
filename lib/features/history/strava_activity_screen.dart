import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/activity.dart';
import '../../core/strava_archive.dart';
import '../../core/track.dart';
import '../../widgets/activity_card.dart';
import '../../widgets/route_map.dart';
import '../../widgets/series_chart.dart';
import '../../widgets/share_capture.dart';

const _zoneColors = [
  Color(0xFF9E9E9E),
  Color(0xFF42A5F5),
  Color(0xFF66BB6A),
  Color(0xFFFFA726),
  Color(0xFFEF5350),
];
const _zoneNames = ['ゾーン1 回復', 'ゾーン2 持久', 'ゾーン3 有酸素', 'ゾーン4 閾値', 'ゾーン5 最大'];

/// Strava から取り込んだ運動1件の詳細（地図・スプリット・グラフ・心拍ゾーン・ベスト記録）
class StravaActivityScreen extends StatefulWidget {
  const StravaActivityScreen({super.key, required this.activityId});

  final String activityId;

  @override
  State<StravaActivityScreen> createState() => _StravaActivityScreenState();
}

class _StravaActivityScreenState extends State<StravaActivityScreen> {
  StravaActivity? _a;
  int _maxHr = 190;
  bool _loaded = false;
  final _shareKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppServices.I.db;
    final a = await db.stravaActivity(widget.activityId);
    final maxHr = await db.stravaMaxHr();
    if (!mounted) return;
    setState(() {
      _a = a;
      if (maxHr != null) _maxHr = maxHr.clamp(150, 215).toInt();
      _loaded = true;
    });
  }

  String _dateText(DateTime d) =>
      '${d.year}/${d.month}/${d.day}（${'月火水木金土日'[d.weekday - 1]}） ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  void _share(StravaActivity a) {
    final parts = [
      a.name.isNotEmpty ? a.name : a.kind.label,
      if (a.distanceM > 0) '${(a.distanceM / 1000).toStringAsFixed(2)}km',
      formatDuration(a.movingS),
      if (a.distanceM > 0 && a.usesPace) '${formatPace(a.movingS / a.distanceM * 1000)}/km',
      if (a.distanceM > 0 && !a.usesPace) '${(a.distanceM / a.movingS * 3.6).toStringAsFixed(1)}km/h',
      if (a.elevGainM != null && a.elevGainM! > 0) '獲得標高${a.elevGainM!.round()}m',
    ];
    shareCapture(context, _shareKey, text: parts.join('・'), fileName: 'activity_${a.id.hashCode.abs()}');
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    return Scaffold(
      appBar: AppBar(
        title: Text(a == null ? '運動' : a.kind.label),
        actions: [if (a != null) ShareButton(onPressed: () => _share(a))],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : a == null
              ? const Center(child: Text('記録が見つかりません'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    ShareFrame(captureKey: _shareKey, child: _headerCard(context, a)),
                    const SizedBox(height: 12),
                    ..._sections(context, a),
                  ],
                ),
    );
  }

  Widget _headerCard(BuildContext context, StravaActivity a) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Icon(ActivityCard.iconFor(a.kind), size: 28, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.name.isNotEmpty ? a.name : a.kind.label,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Text('${_dateText(a.start)}・${a.typeLabel.isNotEmpty ? a.typeLabel : a.kind.label}',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (a.hasRoute)
            Stack(
              children: [
                SizedBox(height: 230, child: RouteMap(track: a.track)),
                Positioned(
                  right: 6,
                  top: 6,
                  child: IconButton.filledTonal(
                    tooltip: '地図を大きく表示',
                    icon: const Icon(Icons.fullscreen),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RouteMapScreen(title: a.name.isNotEmpty ? a.name : a.kind.label, track: a.track),
                    )),
                  ),
                ),
              ],
            ),
          Padding(padding: const EdgeInsets.all(12), child: _statsGrid(context, a)),
        ],
      ),
    );
  }

  Widget _statsGrid(BuildContext context, StravaActivity a) {
    final theme = Theme.of(context);
    final cells = <(String, String)>[
      if (a.distanceM > 0) ('距離', '${(a.distanceM / 1000).toStringAsFixed(2)} km'),
      ('移動時間', formatDuration(a.movingS)),
      if (a.distanceM > 0 && a.usesPace) ('平均ペース', '${formatPace(a.movingS / a.distanceM * 1000)} /km'),
      if (a.distanceM > 0 && !a.usesPace) ('平均速度', '${(a.distanceM / a.movingS * 3.6).toStringAsFixed(1)} km/h'),
      if (a.maxSpeedMps != null && !a.usesPace) ('最高速度', '${(a.maxSpeedMps! * 3.6).toStringAsFixed(1)} km/h'),
      if (a.elevGainM != null) ('獲得標高', '${a.elevGainM!.round()} m'),
      ('経過時間', formatDuration(a.elapsedS)),
      if (a.kcal != null) ('カロリー', '${a.kcal!.round()} kcal'),
      if (a.avgHr != null) ('平均心拍', '${a.avgHr!.round()} bpm'),
      if (a.maxHr != null) ('最大心拍', '${a.maxHr} bpm'),
    ];
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 16) / 3;
      return Wrap(
        spacing: 8,
        runSpacing: 10,
        children: [
          for (final (label, value) in cells)
            SizedBox(
              width: w,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodySmall),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }

  List<Widget> _sections(BuildContext context, StravaActivity a) {
    final pts = a.track.where((p) => p.dist != null).toList();
    final out = <Widget>[];
    if (a.splits.isNotEmpty) out.add(_splitsCard(context, a));
    if (pts.length >= 10) {
      final speed = _speedSeries(pts);
      if (speed != null) {
        out.add(_chartCard(
          context,
          a.usesPace ? 'ペース' : '速度',
          SeriesChart(
            xs: speed.$1,
            ys: a.usesPace ? speed.$2.map((v) => 1000 / v).toList() : speed.$2.map((v) => v * 3.6).toList(),
            color: const Color(0xFF1E88E5),
            invert: a.usesPace,
            format: a.usesPace ? formatPace : (v) => v.toStringAsFixed(0),
          ),
          a.usesPace ? '分/km（上ほど速い）' : 'km/h',
        ));
      }
      final ele = [for (final p in pts) if (p.ele != null) p];
      if (ele.length >= 10) {
        out.add(_chartCard(
          context,
          '標高',
          SeriesChart(
            xs: ele.map((p) => p.dist! / 1000).toList(),
            ys: ele.map((p) => p.ele!).toList(),
            color: const Color(0xFF8D6E63),
            format: (v) => '${v.round()}m',
          ),
          a.elevGainM == null ? null : '獲得標高 ${a.elevGainM!.round()}m',
        ));
      }
      final hr = [for (final p in pts) if (p.hr != null) p];
      if (hr.length >= 10) {
        out.add(_chartCard(
          context,
          '心拍数',
          SeriesChart(
            xs: hr.map((p) => p.dist! / 1000).toList(),
            ys: hr.map((p) => p.hr!.toDouble()).toList(),
            color: const Color(0xFFE53935),
            format: (v) => '${v.round()}',
          ),
          'bpm',
        ));
        out.add(_zonesCard(context, a));
      }
    }
    if (a.bestEfforts.isNotEmpty) out.add(_bestsCard(context, a));
    if (!a.hasRoute && pts.isEmpty) {
      out.add(const Padding(
        padding: EdgeInsets.all(8),
        child: Text('この記録には位置・心拍の詳しいデータがありません（Strava の書き出しにファイルが含まれていない記録です）。'),
      ));
    }
    return out;
  }

  /// 30秒の区間で平均した速度（m/s）。止まっている区間は除く
  (List<double>, List<double>)? _speedSeries(List<TrackPoint> pts) {
    final xs = <double>[];
    final ys = <double>[];
    var j = 0;
    for (var i = 0; i < pts.length; i++) {
      while (j < pts.length && pts[j].time.difference(pts[i].time).inSeconds < 30) {
        j++;
      }
      if (j >= pts.length) break;
      final dt = pts[j].time.difference(pts[i].time).inMilliseconds / 1000;
      final v = (pts[j].dist! - pts[i].dist!) / dt;
      if (v < 0.5 || v > 40) continue;
      xs.add(pts[i].dist! / 1000);
      ys.add(v);
    }
    if (xs.length < 5) return null;
    return (xs, ys);
  }

  Widget _chartCard(BuildContext context, String title, Widget chart, String? note) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: theme.textTheme.labelLarge),
                const Spacer(),
                if (note != null) Text(note, style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            chart,
          ],
        ),
      ),
    );
  }

  Widget _splitsCard(BuildContext context, StravaActivity a) {
    final theme = Theme.of(context);
    final full = a.splits.where((s) => s.distanceM >= 900).toList();
    final paces = full.map((s) => s.paceSecPerKm).toList();
    final fastest = paces.isEmpty ? 0.0 : paces.reduce(math.min);
    final slowest = paces.isEmpty ? 1.0 : paces.reduce(math.max);
    final hasHr = a.splits.any((s) => s.avgHr != null);
    final hasEle = a.splits.any((s) => s.eleDiff != null);
    final small = theme.textTheme.bodySmall;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('スプリット', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Row(
              children: [
                SizedBox(width: 40, child: Text('km', style: small)),
                SizedBox(width: 56, child: Text(a.usesPace ? 'ペース' : '速度', style: small)),
                const Expanded(child: SizedBox()),
                if (hasEle) SizedBox(width: 44, child: Text('標高', textAlign: TextAlign.right, style: small)),
                if (hasHr) SizedBox(width: 40, child: Text('心拍', textAlign: TextAlign.right, style: small)),
              ],
            ),
            for (final s in a.splits)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(s.distanceM >= 900 ? '${s.index}' : (s.distanceM / 1000).toStringAsFixed(1)),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        a.usesPace
                            ? formatPace(s.paceSecPerKm)
                            : (s.distanceM / s.seconds * 3.6).toStringAsFixed(1),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(builder: (context, c) {
                        // 速いほど長い棒
                        final range = slowest - fastest;
                        final f = range <= 0 ? 1.0 : 1 - 0.7 * (s.paceSecPerKm - fastest) / range;
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            height: 10,
                            width: c.maxWidth * f.clamp(0.1, 1.0),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        );
                      }),
                    ),
                    if (hasEle)
                      SizedBox(
                        width: 44,
                        child: Text(
                          s.eleDiff == null ? '' : '${s.eleDiff! >= 0 ? '+' : ''}${s.eleDiff!.round()}',
                          textAlign: TextAlign.right,
                        ),
                      ),
                    if (hasHr)
                      SizedBox(
                        width: 40,
                        child: Text(s.avgHr == null ? '' : '${s.avgHr!.round()}', textAlign: TextAlign.right),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _zonesCard(BuildContext context, StravaActivity a) {
    final theme = Theme.of(context);
    final zones = heartRateZones(a.track, _maxHr);
    final total = zones.fold<double>(0, (x, y) => x + y);
    if (total <= 0) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('心拍ゾーン', style: theme.textTheme.labelLarge),
                const Spacer(),
                Text('最大心拍 $_maxHr bpm 基準', style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            for (var z = 4; z >= 0; z--)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(width: 110, child: Text(_zoneNames[z], style: const TextStyle(fontSize: 12))),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, c) => Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            height: 12,
                            width: math.max(2, c.maxWidth * zones[z] / total),
                            decoration: BoxDecoration(
                              color: _zoneColors[z],
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 74,
                      child: Text(
                        '${formatDuration(zones[z])} ${(zones[z] / total * 100).round()}%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Text(
              '最大心拍は取り込んだ記録の直近1年の最高値です（ゾーンは最大心拍の60・70・80・90%で区切り）',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _bestsCard(BuildContext context, StravaActivity a) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ベストエフォート（この記録内の最速区間）', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            for (final (label, d) in bestEffortDistances)
              if (a.bestEfforts[label] != null)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(label),
                  subtitle: Text('${formatPace(a.bestEfforts[label]! / d * 1000)} /km'),
                  trailing: Text(
                    formatDuration(a.bestEfforts[label]!),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// 一覧などで使う短い表記（km・時間・ペース）
String activitySummary(StravaActivity a) {
  final parts = <String>[
    if (a.distanceM > 0) '${(a.distanceM / 1000).toStringAsFixed(2)}km',
    formatDuration(a.movingS),
    if (a.distanceM > 0 && a.kind != ExerciseKind.biking) '${formatPace(a.movingS / a.distanceM * 1000)}/km',
  ];
  return parts.join('・');
}
