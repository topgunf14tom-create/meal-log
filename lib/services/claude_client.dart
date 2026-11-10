import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ClaudeException implements Exception {
  ClaudeException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => message;
}

class ClaudeReply {
  const ClaudeReply({
    required this.model,
    required this.text,
    required this.inputTokens,
    required this.outputTokens,
    required this.webSearches,
    this.stopReason,
    this.cacheWriteTokens = 0,
    this.cacheReadTokens = 0,
  });

  final String model;

  /// 最終回答のテキスト（検索結果の後ろにあるテキストブロックを連結）
  final String text;
  final int inputTokens;
  final int outputTokens;
  final int webSearches;
  final String? stopReason;

  /// inputTokens のうちキャッシュ書き込み・読み込みの分（料金の計算用）
  final int cacheWriteTokens;
  final int cacheReadTokens;
}

/// Claude Messages API の最小クライアント
class ClaudeClient {
  ClaudeClient({http.Client? client}) : _http = client ?? http.Client();

  static final _endpoint = Uri.parse('https://api.anthropic.com/v1/messages');
  final http.Client _http;

  Future<ClaudeReply> send({
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> content,
    String? system,
    int maxTokens = 1024,
    List<Map<String, dynamic>>? tools,
    Duration timeout = const Duration(seconds: 60),
    bool cacheSystem = false,
  }) async {
    final body = jsonEncode({
      'model': model,
      'max_tokens': maxTokens,
      if (system != null)
        'system': cacheSystem
            ? [
                // 固定の指示文をプロンプトキャッシュの対象にする（2回目以降の入力単価が下がる）
                {'type': 'text', 'text': system, 'cache_control': {'type': 'ephemeral'}},
              ]
            : system,
      if (tools != null) 'tools': tools,
      'messages': [
        {'role': 'user', 'content': content},
      ],
    });
    final headers = {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    };

    ClaudeException? lastError;
    // 失敗時は1回だけ自動リトライ
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 2));
      final http.Response res;
      try {
        res = await _http.post(_endpoint, headers: headers, body: body).timeout(timeout);
      } on TimeoutException {
        lastError = ClaudeException('タイムアウトしました。通信環境を確認してもう一度お試しください');
        continue;
      } on SocketException {
        lastError = ClaudeException('ネットワークに接続できません');
        continue;
      } on http.ClientException catch (e) {
        lastError = ClaudeException('通信エラー: ${e.message}');
        continue;
      }

      final text = utf8.decode(res.bodyBytes);
      if (res.statusCode == 200) return parseReply(model, text);
      final err = _mapError(res.statusCode, text);
      if (_retryable(res.statusCode)) {
        lastError = err;
        continue;
      }
      throw err;
    }
    throw lastError ?? ClaudeException('不明なエラーが発生しました');
  }

  bool _retryable(int status) => status == 429 || status == 529 || status >= 500;

  ClaudeException _mapError(int status, String body) {
    var msg = '';
    var type = '';
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is Map) {
        msg = (j['error']['message'] ?? '').toString();
        type = (j['error']['type'] ?? '').toString();
      }
    } catch (_) {}
    final lower = msg.toLowerCase();

    if (status == 401) {
      return ClaudeException('APIキーが正しくありません（401）。キーを貼り直してください', status: status);
    }
    if (lower.contains('credit balance') || lower.contains('billing')) {
      return ClaudeException('クレジット残高が不足しています。Consoleでクレジットを購入してください', status: status);
    }
    if (status == 403) {
      return ClaudeException('このAPIキーでは利用できません（403）: $msg', status: status);
    }
    if (status == 404 || type == 'not_found_error') {
      return ClaudeException('モデルが見つかりません。設定のモデルIDを確認してください: $msg', status: status);
    }
    if (status == 429) {
      return ClaudeException('利用上限に達しました（429）。少し待つか、Consoleの利用上限を確認してください', status: status);
    }
    if (status == 529 || status >= 500) {
      return ClaudeException('Claude側が混み合っています（$status）。少し待ってから再試行してください', status: status);
    }
    return ClaudeException('エラー（$status）: $msg', status: status);
  }
}

/// レスポンス本文から最終回答のテキストと使用量を取り出す
ClaudeReply parseReply(String requestedModel, String body) {
  final j = jsonDecode(body) as Map<String, dynamic>;
  final blocks = (j['content'] as List? ?? const []).whereType<Map>().toList();

  // Web検索を使った場合、最後の検索結果より後ろのテキストが最終回答
  var start = 0;
  for (var i = 0; i < blocks.length; i++) {
    final t = blocks[i]['type'];
    if (t == 'server_tool_use' || t == 'web_search_tool_result' || t == 'web_fetch_tool_result') {
      start = i + 1;
    }
  }
  String joinText(Iterable<Map> bs) =>
      bs.where((b) => b['type'] == 'text').map((b) => (b['text'] ?? '').toString()).join();
  var text = joinText(blocks.skip(start));
  if (text.trim().isEmpty) text = joinText(blocks);

  final usage = (j['usage'] as Map?) ?? const {};
  int n(Object? v) => (v as num?)?.toInt() ?? 0;
  final serverTool = usage['server_tool_use'] as Map?;

  return ClaudeReply(
    model: requestedModel,
    text: text,
    inputTokens: n(usage['input_tokens']) +
        n(usage['cache_creation_input_tokens']) +
        n(usage['cache_read_input_tokens']),
    outputTokens: n(usage['output_tokens']),
    webSearches: n(serverTool?['web_search_requests']),
    stopReason: j['stop_reason']?.toString(),
    cacheWriteTokens: n(usage['cache_creation_input_tokens']),
    cacheReadTokens: n(usage['cache_read_input_tokens']),
  );
}
