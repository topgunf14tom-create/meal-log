import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/track.dart';

/// 地図タイルの取得元（OpenStreetMap）。仕様上、Claude API 以外の唯一の通信先
const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _userAgentPackage = 'com.masayuki.meallog.meal_log';

/// 運動のルートを地図の上に表示する
class RouteMap extends StatelessWidget {
  const RouteMap({super.key, required this.track, this.interactive = false});

  final List<TrackPoint> track;

  /// false なら指での操作を受け付けない（一覧・共有用）
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final pts = [
      for (final p in track)
        if (p.hasPosition) LatLng(p.lat!, p.lon!),
    ];
    if (pts.isEmpty) return const SizedBox.shrink();
    final bounds = LatLngBounds.fromPoints(pts);
    final tiny = (bounds.north - bounds.south).abs() < 0.0005 && (bounds.east - bounds.west).abs() < 0.0005;
    return FlutterMap(
      options: MapOptions(
        initialCenter: bounds.center,
        initialZoom: 15,
        initialCameraFit: tiny
            ? null
            : CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(28), maxZoom: 17),
        interactionOptions: InteractionOptions(
          flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(urlTemplate: _tileUrl, userAgentPackageName: _userAgentPackage, maxZoom: 19),
        PolylineLayer(
          polylines: [
            Polyline(
              points: pts,
              strokeWidth: 4,
              color: const Color(0xFFFC4C02),
              borderStrokeWidth: 1.5,
              borderColor: Colors.white,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(point: pts.first, width: 16, height: 16, child: const _Dot(color: Color(0xFF2E7D32))),
            Marker(point: pts.last, width: 16, height: 16, child: const _Dot(color: Color(0xFFC62828))),
          ],
        ),
        RichAttributionWidget(
          showFlutterMapAttribution: false,
          attributions: [
            TextSourceAttribution(
              'OpenStreetMap contributors',
              onTap: () => launchUrl(Uri.parse('https://openstreetmap.org/copyright'),
                  mode: LaunchMode.externalApplication),
            ),
          ],
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
        ),
      );
}

/// 全画面の地図
class RouteMapScreen extends StatelessWidget {
  const RouteMapScreen({super.key, required this.title, required this.track});

  final String title;
  final List<TrackPoint> track;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: RouteMap(track: track, interactive: true),
      );
}
