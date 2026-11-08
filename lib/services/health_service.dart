import 'dart:io';

import 'package:flutter/services.dart';

import '../core/activity.dart';

/// ヘルスコネクトの状態
enum HealthStatus {
  available,

  /// ヘルスコネクトの更新が必要
  updateRequired,

  /// 未対応端末（iOS など）
  unavailable,
}

/// 時刻つきの測定値（体重 kg・体脂肪 %・身長 m など）
class HealthSample {
  const HealthSample(this.time, this.value, this.origin);

  final DateTime time;
  final double value;
  final String origin;

  static List<HealthSample> listFrom(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((m) {
      return HealthSample(
        DateTime.fromMillisecondsSinceEpoch((m['time'] as num?)?.toInt() ?? 0),
        (m['value'] as num?)?.toDouble() ?? 0,
        m['origin']?.toString() ?? '',
      );
    }).toList();
  }
}

class BodySamples {
  const BodySamples({
    this.weight = const [],
    this.bodyFat = const [],
    this.leanMass = const [],
    this.height = const [],
  });

  final List<HealthSample> weight;
  final List<HealthSample> bodyFat;
  final List<HealthSample> leanMass;
  final List<HealthSample> height;
}

/// Android の MainActivity（tool/android/MainActivity.kt）と MethodChannel で通信する。
/// 読み取りのみ。データは端末の外に出さない。
class HealthService {
  static const _ch = MethodChannel('meal_log/health');

  /// 必要な権限のキー（Kotlin 側と同じ）
  static const allKeys = ['weight', 'bodyFat', 'leanMass', 'height', 'steps', 'exercise', 'activeKcal'];

  static const keyLabels = {
    'weight': '体重',
    'bodyFat': '体脂肪率',
    'leanMass': '除脂肪量',
    'height': '身長',
    'steps': '歩数',
    'exercise': 'エクササイズ',
    'activeKcal': '活動カロリー',
  };

  bool get _supported => Platform.isAndroid;

  Future<HealthStatus> status() async {
    if (!_supported) return HealthStatus.unavailable;
    try {
      final s = await _ch.invokeMethod<String>('status');
      return switch (s) {
        'available' => HealthStatus.available,
        'update_required' => HealthStatus.updateRequired,
        _ => HealthStatus.unavailable,
      };
    } on PlatformException {
      return HealthStatus.unavailable;
    } on MissingPluginException {
      return HealthStatus.unavailable;
    }
  }

  /// 許可済みの権限キー
  Future<Set<String>> granted() async {
    if (!_supported) return {};
    try {
      final list = await _ch.invokeListMethod<String>('granted');
      return (list ?? const []).toSet();
    } on PlatformException {
      return {};
    } on MissingPluginException {
      return {};
    }
  }

  /// 権限画面を開き、閉じた後の許可済みキーを返す
  Future<Set<String>> request() async {
    if (!_supported) return {};
    final list = await _ch.invokeListMethod<String>('request');
    return (list ?? const []).toSet();
  }

  Future<bool> openSettings() async {
    if (!_supported) return false;
    try {
      return await _ch.invokeMethod<bool>('openSettings') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<BodySamples> readBody(DateTime from, DateTime to) async {
    final m = await _ch.invokeMapMethod<String, Object?>('readBody', {
      'start': from.millisecondsSinceEpoch,
      'end': to.millisecondsSinceEpoch,
    });
    if (m == null) return const BodySamples();
    return BodySamples(
      weight: HealthSample.listFrom(m['weight']),
      bodyFat: HealthSample.listFrom(m['bodyFat']),
      leanMass: HealthSample.listFrom(m['leanMass']),
      height: HealthSample.listFrom(m['height']),
    );
  }

  Future<List<ExerciseSession>> readSessions(DateTime from, DateTime to) async {
    final list = await _ch.invokeListMethod<Object?>('readSessions', {
      'start': from.millisecondsSinceEpoch,
      'end': to.millisecondsSinceEpoch,
    });
    return (list ?? const []).whereType<Map>().map((m) {
      return ExerciseSession(
        start: DateTime.fromMillisecondsSinceEpoch((m['start'] as num?)?.toInt() ?? 0),
        end: DateTime.fromMillisecondsSinceEpoch((m['end'] as num?)?.toInt() ?? 0),
        kind: ExerciseKind.fromKey(m['type']?.toString()),
        title: m['title']?.toString(),
        origin: m['origin']?.toString() ?? '',
      );
    }).toList();
  }

  /// 区間ごとの歩数・活動カロリー（ヘルスコネクト側で重複除去）
  Future<List<RangeTotals>> aggregate(List<(DateTime, DateTime)> ranges) async {
    if (ranges.isEmpty) return const [];
    final list = await _ch.invokeListMethod<Object?>('aggregate', {
      'ranges': [
        for (final (s, e) in ranges) [s.millisecondsSinceEpoch, e.millisecondsSinceEpoch],
      ],
    });
    return (list ?? const []).map((raw) {
      final m = raw is Map ? raw : const {};
      return RangeTotals(
        steps: (m['steps'] as num?)?.toInt(),
        kcal: (m['kcal'] as num?)?.toDouble(),
      );
    }).toList();
  }
}
