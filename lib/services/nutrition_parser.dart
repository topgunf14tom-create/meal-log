import 'dart:convert';

import '../data/entities.dart';

class ParsedNutrition {
  const ParsedNutrition(this.items, this.note);

  final List<MealItem> items;
  final String? note;
}

/// Claude の回答（JSON）を料理リストに変換する
class NutritionParser {
  static ParsedNutrition parse(String raw) {
    final text = raw.trim();
    Object? decoded = _tryDecode(text);
    if (decoded is! Map) {
      // 前置きやコードブロックが付いた場合：最初の { から最後の } までを再パース
      final s = text.indexOf('{');
      final e = text.lastIndexOf('}');
      if (s >= 0 && e > s) decoded = _tryDecode(text.substring(s, e + 1));
    }
    if (decoded is! Map) {
      throw const FormatException('解析結果（JSON）を読み取れませんでした');
    }

    final items = <MealItem>[];
    final list = decoded['items'];
    if (list is List) {
      for (final e in list) {
        if (e is Map) items.add(MealItem.fromJson(e.cast<String, dynamic>()));
      }
    }
    final note = decoded['note']?.toString().trim();
    return ParsedNutrition(items, (note == null || note.isEmpty || note == 'null') ? null : note);
  }

  static Object? _tryDecode(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }
}
