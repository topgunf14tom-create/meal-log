import 'dart:convert';
import 'dart:typed_data';

import '../core/text_normalize.dart';
import '../data/app_db.dart';
import '../data/app_settings.dart';
import '../data/entities.dart';
import 'claude_client.dart';
import 'image_service.dart';
import 'key_store.dart';
import 'nutrition_parser.dart';
import 'prompts.dart';

class MissingApiKeyException implements Exception {
  @override
  String toString() => 'APIキーが設定されていません';
}

class AnalysisResult {
  const AnalysisResult({required this.items, required this.model, this.note, this.fromCache = false});

  final List<MealItem> items;
  final String model;
  final String? note;
  final bool fromCache;
}

/// 写真解析・チェーン店検索・接続テスト
class NutritionService {
  NutritionService({required this.claude, required this.db, required this.settings, required this.keys});

  final ClaudeClient claude;
  final AppDb db;
  final AppSettings settings;
  final KeyStore keys;

  Future<String> _apiKey() async {
    final k = await keys.read();
    if (k == null) throw MissingApiKeyException();
    return k;
  }

  Map<String, dynamic> _imageBlock(Uint8List bytes) => {
        'type': 'image',
        'source': {'type': 'base64', 'media_type': mediaTypeOf(bytes), 'data': base64Encode(bytes)},
      };

  /// 写真解析（通常は Haiku、reanalyze=true で Sonnet）
  Future<AnalysisResult> analyzePhoto(Uint8List jpeg, {String? hint, bool reanalyze = false}) async {
    final key = await _apiKey();
    final model = reanalyze ? settings.reanalyzeModel : settings.photoModel;
    final h = hint?.trim() ?? '';
    final reply = await claude.send(
      apiKey: key,
      model: model,
      system: Prompts.photo,
      maxTokens: reanalyze ? 1500 : 1024,
      content: [
        _imageBlock(jpeg),
        {
          'type': 'text',
          'text': h.isEmpty ? 'この食事の栄養価をJSONで出力してください。' : '補足: $h\nこの食事の栄養価をJSONで出力してください。',
        },
      ],
    );
    await _log(reply, reanalyze ? 'reanalyze' : 'photo');
    final parsed = NutritionParser.parse(reply.text);
    return AnalysisResult(items: parsed.items, note: parsed.note, model: model);
  }

  /// チェーン店メニュー検索（キャッシュ優先、無ければ Sonnet + Web検索）
  Future<AnalysisResult> lookupChain({required String store, required String menu, Uint8List? photo}) async {
    final storeKey = normalizeKey(store);
    final menuKey = normalizeKey(menu);
    final cached = await db.findChain(storeKey, menuKey);
    if (cached != null && cached.isNotEmpty) {
      return AnalysisResult(items: cached, model: 'cache', note: '保存済みの公式データを使用（API未使用）', fromCache: true);
    }

    final key = await _apiKey();
    final model = settings.chainModel;
    final content = <Map<String, dynamic>>[
      if (photo != null) _imageBlock(photo),
      {
        'type': 'text',
        'text': '店名: $store\nメニュー: $menu\n公式サイトの栄養成分表を検索し、JSONで出力してください。',
      },
    ];

    Future<ClaudeReply> request(String toolType) => claude.send(
          apiKey: key,
          model: model,
          system: Prompts.chain,
          maxTokens: 2048,
          timeout: const Duration(seconds: 120),
          tools: [
            {'type': toolType, 'name': 'web_search', 'max_uses': 3},
          ],
          content: content,
        );

    ClaudeReply reply;
    try {
      reply = await request('web_search_20260209');
    } on ClaudeException catch (e) {
      // 新しいツール版に未対応のモデルを設定した場合は旧版で再試行
      if (e.status == 400 && e.message.contains('web_search')) {
        reply = await request('web_search_20250305');
      } else {
        rethrow;
      }
    }
    await _log(reply, 'chain');

    final parsed = NutritionParser.parse(reply.text);
    if (parsed.items.isNotEmpty && parsed.items.every((i) => i.sourceType == 'official')) {
      await db.saveChain(storeKey, menuKey, '$store $menu', parsed.items);
    }
    return AnalysisResult(items: parsed.items, note: parsed.note, model: model);
  }

  /// 接続テスト：短いテキストを1回送る
  Future<void> testKey(String apiKey) async {
    final model = settings.photoModel;
    final reply = await claude.send(
      apiKey: apiKey,
      model: model,
      maxTokens: 8,
      content: [
        {'type': 'text', 'text': 'ping'},
      ],
    );
    await _log(reply, 'test');
  }

  Future<void> _log(ClaudeReply r, String purpose) => db.addUsage(
        model: r.model,
        purpose: purpose,
        inputTokens: r.inputTokens,
        outputTokens: r.outputTokens,
        webSearches: r.webSearches,
        costUsd: settings.prices.costUsd(r.model, r.inputTokens, r.outputTokens, r.webSearches),
      );
}
