import "dart:convert";
import "dart:io";
import "package:flutter/foundation.dart";
import "package:http/http.dart" as http;
import "package:path_provider/path_provider.dart";
import "models.dart";

class LlmAskResult {
  final String answer;
  final String url;
  final Map<String, String> headers;
  final Map<String, dynamic> payload;
  final int statusCode;

  LlmAskResult({
    required this.answer,
    required this.url,
    required this.headers,
    required this.payload,
    required this.statusCode,
  });
}

class ApiService {
  final String baseUrl;
  ApiService(this.baseUrl);
  static String? _cachedLogPath;

  String _buildUrl(String path) {
    final normalizedBase = baseUrl.endsWith("/")
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = path.startsWith("/") ? path : "/$path";
    return "$normalizedBase$normalizedPath";
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final url = Uri.parse("$baseUrl$path");
    final resp = await http
        .post(
          url,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 120));

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception("HTTP ${resp.statusCode}: ${resp.body}");
    }
    final data = jsonDecode(resp.body);
    if (data is! Map<String, dynamic>) {
      throw Exception("Unexpected response: ${resp.body}");
    }
    return data;
  }

  Future<String?> getGeneLlmLogPath() async {
    if (kIsWeb) return null;
    if (_cachedLogPath != null) return _cachedLogPath;
    final dir = await getApplicationDocumentsDirectory();
    _cachedLogPath = "${dir.path}/genellm_requests.log";
    return _cachedLogPath;
  }

  Future<void> _appendGeneLlmLog(String message) async {
    try {
      final path = await getGeneLlmLogPath();
      if (path == null) return;
      final file = File(path);
      final ts = DateTime.now().toIso8601String();
      await file.writeAsString("[$ts] $message\n", mode: FileMode.append);
    } catch (_) {
      // ignore log write failures; never break main request path.
    }
  }

  String _extractLlmText(dynamic data) {
    String? llmText;
    if (data is String) {
      llmText = data;
    } else if (data is Map<String, dynamic>) {
      for (final key in [
        "text",
        "answer",
        "content",
        "result",
        "output",
        "message",
      ]) {
        final v = data[key];
        if (v is String && v.trim().isNotEmpty) {
          llmText = v;
          break;
        }
      }
      if ((llmText == null || llmText.isEmpty) &&
          data["choices"] is List &&
          (data["choices"] as List).isNotEmpty) {
        final c0 = (data["choices"] as List).first;
        if (c0 is Map<String, dynamic>) {
          final fromMessage = (c0["message"] is Map<String, dynamic>)
              ? (c0["message"]["content"]?.toString())
              : null;
          llmText = fromMessage ?? c0["text"]?.toString();
        }
      }
    }
    if (llmText == null || llmText.trim().isEmpty) {
      llmText = jsonEncode(data);
    }
    return llmText.trim();
  }

  Future<LlmAskResult> askLlm({
    required String userId,
    required String aggregatedQuery,
    required String topic,
    required List<String> variants,
    dynamic yuguard,
    bool debugMode = false,
  }) async {
    final endpoint = _buildUrl("/v1/ask");
    final url = Uri.parse(endpoint);
    final payload = {
      "user_id": userId,
      "query": aggregatedQuery,
      "topic": topic,
      "SNP_list": variants,
      "snp_list": variants,
      "variants": variants,
      "yuguard": yuguard,
    };
    final headers = <String, String>{"Content-Type": "application/json"};
    if (debugMode && kDebugMode) {
      debugPrint("[GeneLLM] POST $endpoint");
      debugPrint("[GeneLLM] headers=$headers");
      debugPrint(
        "[GeneLLM] payload=${const JsonEncoder.withIndent("  ").convert(payload)}",
      );
    }
    if (debugMode) {
      await _appendGeneLlmLog(
        "REQUEST url=$endpoint headers=$headers payload=${jsonEncode(payload)}",
      );
    }
    final resp = await http
        .post(
          url,
          headers: headers,
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 600));
    if (debugMode && kDebugMode) {
      debugPrint("[GeneLLM] status=${resp.statusCode}");
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      if (debugMode) {
        await _appendGeneLlmLog(
          "RESPONSE status=${resp.statusCode} body=${resp.body}",
        );
      }
      throw Exception("HTTP ${resp.statusCode}: ${resp.body}");
    }
    dynamic data;
    try {
      data = jsonDecode(resp.body);
    } catch (_) {
      final raw = resp.body.trim();
      final answer = raw.length > 4000 ? raw.substring(0, 4000) : raw;
      if (debugMode && kDebugMode) {
        debugPrint("[GeneLLM] response_raw=$answer");
      }
      if (debugMode) {
        await _appendGeneLlmLog(
          "RESPONSE status=${resp.statusCode} raw_body=${answer.replaceAll("\n", "\\n")}",
        );
      }
      return LlmAskResult(
        answer: answer,
        url: endpoint,
        headers: headers,
        payload: payload,
        statusCode: resp.statusCode,
      );
    }

    final text = _extractLlmText(data);
    final answer = text.length > 4000 ? text.substring(0, 4000) : text;
    if (debugMode && kDebugMode) {
      debugPrint("[GeneLLM] response_text=$answer");
    }
    if (debugMode) {
      await _appendGeneLlmLog(
        "RESPONSE status=${resp.statusCode} parsed_answer=${answer.replaceAll("\n", "\\n")}",
      );
    }
    return LlmAskResult(
      answer: answer,
      url: endpoint,
      headers: headers,
      payload: payload,
      statusCode: resp.statusCode,
    );
  }

  Future<List<RagChunk>> retrieve({
    required String query,
    required ChatTopic topic,
    int topK = 4,
  }) async {
    final data = await _postJson("/v1/retrieve", {
      "query": query,
      "topic": topic.key,
      "top_k": topK,
    });
    final rows = (data["chunks"] as List?) ?? const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map((r) {
          return RagChunk(
            source: (r["source"] ?? "unknown").toString(),
            content: (r["content"] ?? "").toString(),
            score: (r["score"] as num?)?.toDouble(),
          );
        })
        .where((c) => c.content.trim().isNotEmpty)
        .toList();
  }

  Future<ToolResult> callTool({
    required String tool,
    required String query,
  }) async {
    final data = await _postJson("/v1/tools/$tool", {"query": query});
    final content =
        (data["result"] ?? data["text"] ?? data["content"])?.toString();
    if (content == null || content.trim().isEmpty) {
      throw Exception("Tool [$tool] bad response: $data");
    }
    return ToolResult(tool: tool, content: content.trim());
  }
}
