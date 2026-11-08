import 'package:flutter_test/flutter_test.dart';
import 'package:meal_log/services/claude_client.dart';
import 'package:meal_log/services/nutrition_parser.dart';

void main() {
  group('NutritionParser', () {
    test('JSONのみの回答を読める', () {
      const raw = '{"items":[{"name":"牛丼 並盛","amount":1,"unit":"杯","grams":380,"kcal":635,'
          '"protein_g":20.2,"fat_g":20.9,"carbs_g":92.8,"confidence":"high","source_type":"official",'
          '"source_url":"https://example.com"}],"note":"並盛"}';
      final r = NutritionParser.parse(raw);
      expect(r.items, hasLength(1));
      final i = r.items.first;
      expect(i.name, '牛丼 並盛');
      expect(i.kcal, 635);
      expect(i.protein, 20.2);
      expect(i.grams, 380);
      expect(i.sourceType, 'official');
      expect(i.sourceUrl, 'https://example.com');
      expect(r.note, '並盛');
    });

    test('前置きやコードブロック付きでも読める', () {
      const raw = '結果です。\n```json\n{"items":[{"name":"ご飯","kcal":"234kcal","protein_g":"3.8"}]}\n```';
      final r = NutritionParser.parse(raw);
      expect(r.items.single.name, 'ご飯');
      expect(r.items.single.kcal, 234);
      expect(r.items.single.protein, 3.8);
    });

    test('不正な値は既定値に丸める', () {
      const raw = '{"items":[{"name":"","confidence":"とても高い","source_type":"web","source_url":"null"}],"note":null}';
      final i = NutritionParser.parse(raw).items.single;
      expect(i.name, '不明な料理');
      expect(i.confidence, 'medium');
      expect(i.sourceType, 'estimate');
      expect(i.sourceUrl, isNull);
      expect(i.amount, 1);
      expect(i.unit, '人前');
    });

    test('items が無ければ空リスト', () {
      final r = NutritionParser.parse('{"items":[],"note":"料理が写っていません"}');
      expect(r.items, isEmpty);
      expect(r.note, '料理が写っていません');
    });

    test('JSONが無ければ FormatException', () {
      expect(() => NutritionParser.parse('解析できませんでした'), throwsFormatException);
    });
  });

  group('parseReply', () {
    test('Web検索付き回答は最後のテキストを使い、使用量を合算する', () {
      const body = '{"content":['
          '{"type":"text","text":"検索します"},'
          '{"type":"server_tool_use","id":"s1","name":"web_search","input":{}},'
          '{"type":"web_search_tool_result","tool_use_id":"s1","content":[]},'
          '{"type":"text","text":"{\\"items\\":[]}"}],'
          '"usage":{"input_tokens":100,"cache_read_input_tokens":50,"output_tokens":20,'
          '"server_tool_use":{"web_search_requests":2}},"stop_reason":"end_turn"}';
      final r = parseReply('claude-sonnet-5', body);
      expect(r.text, '{"items":[]}');
      expect(r.inputTokens, 150);
      expect(r.outputTokens, 20);
      expect(r.webSearches, 2);
    });
  });
}
