import 'dart:convert';
import 'dart:typed_data';

import '../core/label_text.dart';
import '../core/photo_judge.dart';
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

/// 写真判定の結果
class JudgeResult {
  const JudgeResult(this.judgement, this.model);

  final PhotoJudgement judgement;
  final String model;
}

class AnalysisResult {
  const AnalysisResult({required this.items, required this.model, this.note, this.fromCache = false});

  final List<MealItem> items;
  final String model;
  final String? note;
  final bool fromCache;
}

/// 写真判定・ラベル転記・チェーン店のWeb検索・振り返り・接続テスト
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

  /// 写真判定：Haiku へ1コール。料理名候補・量感クラス・寸法だけを受け取り、栄養数値は出させない。
  /// [reanalyze] は利用者が明示的に選んだときだけ（設定の再解析モデルで同じ判定をし直す）
  Future<JudgeResult> judgePhoto(Uint8List top, {Uint8List? side, String? hint, bool reanalyze = false}) async {
    final key = await _apiKey();
    final model = reanalyze ? settings.reanalyzeModel : settings.photoModel;
    final h = hint?.trim() ?? '';
    final reply = await claude.send(
      apiKey: key,
      model: model,
      system: Prompts.judge,
      cacheSystem: true,
      maxTokens: 500,
      content: [
        {'type': 'text', 'text': '1枚目（真上）'},
        _imageBlock(top),
        if (side != null) ...[
          {'type': 'text', 'text': '2枚目（斜め約45°）'},
          _imageBlock(side),
        ],
        {'type': 'text', 'text': h.isEmpty ? '判定をJSONで出力してください。' : '補足: $h\n判定をJSONで出力してください。'},
      ],
    );
    await _log(reply, reanalyze ? 'reanalyze' : 'photo');
    return JudgeResult(parsePhotoJudgement(reply.text), model);
  }

  /// 判定の訂正：画像は再送せず、前回の判定（JSON）と訂正の文章だけを送る
  Future<JudgeResult> refineJudgement(String previousJson, String instruction) async {
    final key = await _apiKey();
    final model = settings.photoModel;
    final reply = await claude.send(
      apiKey: key,
      model: model,
      system: Prompts.judge,
      cacheSystem: true,
      maxTokens: 500,
      content: [
        {'type': 'text', 'text': Prompts.refine(previousJson, instruction)},
      ],
    );
    await _log(reply, 'refine');
    return JudgeResult(parsePhotoJudgement(reply.text), model);
  }

  /// 栄養成分表示の転記（端末OCRで読めなかったときのフォールバック）
  Future<({LabelValues values, String? jan})> transcribeLabel(Uint8List jpeg) async {
    final key = await _apiKey();
    final model = settings.photoModel;
    final reply = await claude.send(
      apiKey: key,
      model: model,
      system: Prompts.label,
      cacheSystem: true,
      maxTokens: 300,
      content: [
        _imageBlock(jpeg),
        {'type': 'text', 'text': '栄養成分表示をJSONで転記してください。'},
      ],
    );
    await _log(reply, 'label');
    return parseLabelJson(reply.text);
  }

  /// 週・月の振り返りコメント（写真解析と同じモデル。集計の JSON だけを送る）
  Future<String> reportComment(Map<String, Object?> summary) async {
    final key = await _apiKey();
    final model = settings.photoModel;
    final reply = await claude.send(
      apiKey: key,
      model: model,
      system: Prompts.report,
      maxTokens: 700,
      content: [
        {'type': 'text', 'text': jsonEncode(summary)},
      ],
    );
    await _log(reply, 'report');
    return reply.text.trim();
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
        costUsd: settings.prices.costUsd(r.model, r.inputTokens, r.outputTokens, r.webSearches,
            cacheWriteTokens: r.cacheWriteTokens, cacheReadTokens: r.cacheReadTokens),
      );
}
