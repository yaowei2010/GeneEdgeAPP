import "dart:convert";
import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:uuid/uuid.dart";
import "api_service.dart";
import "ble_gateway.dart";
import "models.dart";

class TopicStrategy {
  final String systemPrompt;
  final List<String> defaultTools;
  final List<String> llmTriggerKeywords;
  final int ragTopK;
  final int contextWindow;

  const TopicStrategy({
    required this.systemPrompt,
    required this.defaultTools,
    required this.llmTriggerKeywords,
    required this.ragTopK,
    required this.contextWindow,
  });
}

class _LlmReply {
  final String answer;
  final String source;
  final String? jobId;
  final Map<String, dynamic>? requestLog;

  const _LlmReply({
    required this.answer,
    required this.source,
    this.jobId,
    this.requestLog,
  });
}

class _EdgeResult {
  final String jobId;
  final Map<String, dynamic> state;

  const _EdgeResult({
    required this.jobId,
    required this.state,
  });
}

class _LlmInputBundle {
  final String userId;
  final String query;
  final String topic;
  final List<String> variants;
  final dynamic yuguard;

  const _LlmInputBundle({
    required this.userId,
    required this.query,
    required this.topic,
    required this.variants,
    required this.yuguard,
  });
}

class ChatController extends ChangeNotifier {
  static const List<ChatTopic> selectableTopics = [
    ChatTopic.alcohol,
    ChatTopic.medication,
    ChatTopic.memory,
    ChatTopic.mentalState,
    ChatTopic.hypertension,
    ChatTopic.lipids,
    ChatTopic.nutrition,
  ];

  final ApiService api;
  final BleGateway? bleGateway;
  final bool preferEdgeBleForLlm;
  final bool allowCloudFallbackWhenBleFails;
  final Map<String, dynamic>? localMockPayload;
  final String? llmUserId;
  final String threadId;
  ChatTopic topic;
  List<String> snpList;

  final _uuid = Uuid();
  final List<ChatMessage> messages = [];
  String? preferredBleDeviceId;
  String? preferredBleDeviceLabel;
  bool geneLlmEnabled = false;
  bool llmDebugMode = false;
  bool useLocalComputeMode = false;

  ChatController({
    required this.api,
    required this.threadId,
    this.bleGateway,
    this.llmUserId,
    this.preferEdgeBleForLlm = true,
    this.allowCloudFallbackWhenBleFails = true,
    this.localMockPayload,
    this.useLocalComputeMode = false,
    this.topic = ChatTopic.alcohol,
    this.snpList = const [],
  });

  static String _storageKey(String threadId) => "chat_thread_$threadId";

  static const Map<ChatTopic, TopicStrategy> _topicStrategies = {
    ChatTopic.alcohol: TopicStrategy(
      systemPrompt: "你是健康助理。主題是酒精代謝與風險，請先評估使用者問題屬於一般資訊、風險提醒、或就醫建議，再用分點回答。",
      defaultTools: ["db"],
      llmTriggerKeywords: [],
      ragTopK: 4,
      contextWindow: 30,
    ),
    ChatTopic.medication: TopicStrategy(
      systemPrompt: "你是健康助理。主題是藥物與個人差異，請避免直接給處方，並提醒與醫師確認。",
      defaultTools: ["db"],
      llmTriggerKeywords: [],
      ragTopK: 4,
      contextWindow: 30,
    ),
    ChatTopic.memory: TopicStrategy(
      systemPrompt: "你是健康助理。主題是記憶與認知，請先區分一般建議與需要就醫評估的情況。",
      defaultTools: ["db"],
      llmTriggerKeywords: [],
      ragTopK: 4,
      contextWindow: 30,
    ),
    ChatTopic.mentalState: TopicStrategy(
      systemPrompt: "你是健康助理。主題是心理狀態，回覆需同理、清楚，遇到高風險訊號需建議立即求助。",
      defaultTools: ["db"],
      llmTriggerKeywords: [],
      ragTopK: 4,
      contextWindow: 30,
    ),
    ChatTopic.hypertension: TopicStrategy(
      systemPrompt: "你是健康助理。主題是高血壓，回覆要提供生活管理重點並提醒定期量測與就醫。",
      defaultTools: ["db"],
      llmTriggerKeywords: [],
      ragTopK: 4,
      contextWindow: 30,
    ),
    ChatTopic.lipids: TopicStrategy(
      systemPrompt: "你是健康助理。主題是血脂管理，請提供飲食/運動重點與必要的醫療追蹤提醒。",
      defaultTools: ["db"],
      llmTriggerKeywords: [],
      ragTopK: 4,
      contextWindow: 30,
    ),
    ChatTopic.nutrition: TopicStrategy(
      systemPrompt: "你是健康助理。主題是營養，回覆請具體且可執行，避免誇大療效。",
      defaultTools: ["db"],
      llmTriggerKeywords: [],
      ragTopK: 4,
      contextWindow: 30,
    ),
  };

  TopicStrategy get _currentStrategy => _topicStrategies[topic]!;

  static String _systemPromptForTopic(ChatTopic topic) =>
      _topicStrategies[topic]!.systemPrompt;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_storageKey(threadId));
    if (raw == null) {
      _ensureSystemPrompt();
      await _save();
      notifyListeners();
      return;
    }

    final decoded = jsonDecode(raw);
    messages.clear();
    if (decoded is List) {
      final arr = decoded.cast<Map<String, dynamic>>();
      messages.addAll(arr.map(ChatMessage.fromJson));
    } else if (decoded is Map<String, dynamic>) {
      final topicRaw = decoded["topic"]?.toString();
      if (topicRaw != null && topicRaw.trim().isNotEmpty) {
        try {
          topic = ChatTopic.fromInput(topicRaw);
        } catch (_) {}
      }
      preferredBleDeviceId = decoded["preferred_ble_device_id"]?.toString();
      preferredBleDeviceLabel =
          decoded["preferred_ble_device_label"]?.toString();
      geneLlmEnabled = (decoded["gene_llm_enabled"] as bool?) ?? false;
      llmDebugMode = (decoded["llm_debug_mode"] as bool?) ?? false;
      useLocalComputeMode =
          (decoded["use_local_compute_mode"] as bool?) ?? useLocalComputeMode;
      final arr =
          (decoded["messages"] as List?)?.cast<Map<String, dynamic>>() ??
              const [];
      messages.addAll(arr.map(ChatMessage.fromJson));
    }
    if (!hasBleGateway && canUseLocalMock) {
      useLocalComputeMode = true;
    }
    _ensureSystemPrompt();
    notifyListeners();
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _storageKey(threadId),
      jsonEncode({
        "topic": topic.key,
        "preferred_ble_device_id": preferredBleDeviceId,
        "preferred_ble_device_label": preferredBleDeviceLabel,
        "gene_llm_enabled": geneLlmEnabled,
        "llm_debug_mode": llmDebugMode,
        "use_local_compute_mode": useLocalComputeMode,
        "messages": messages.map((m) => m.toJson()).toList(),
      }),
    );
  }

  String get bleDeviceDisplayName => preferredBleDeviceLabel ?? "Auto";
  bool get hasBleGateway => bleGateway != null;
  bool get canUseLocalMock => localMockPayload != null;
  String get computeModeLabel => useLocalComputeMode ? "Local JSON" : "BLE";

  Future<List<Map<String, dynamic>>> scanBleDevices() async {
    if (bleGateway == null) return const [];
    final rows = await bleGateway!.scanNearbyDevices();
    return rows
        .map((e) => {"id": e.id, "name": e.name, "rssi": e.rssi})
        .toList();
  }

  Future<void> setPreferredBleDevice({
    required String? id,
    required String? label,
  }) async {
    preferredBleDeviceId = id;
    preferredBleDeviceLabel = label;
    notifyListeners();
    await _save();
  }

  Future<void> setTopic(ChatTopic nextTopic) async {
    if (topic == nextTopic) return;
    topic = nextTopic;
    _ensureSystemPrompt();
    notifyListeners();
    await _save();
  }

  Future<void> setGeneLlmEnabled(bool value) async {
    geneLlmEnabled = value;
    notifyListeners();
    await _save();
  }

  Future<void> toggleGeneLlm() async {
    await setGeneLlmEnabled(!geneLlmEnabled);
  }

  Future<void> setLlmDebugMode(bool value) async {
    llmDebugMode = value;
    notifyListeners();
    await _save();
  }

  Future<void> toggleLlmDebugMode() async {
    await setLlmDebugMode(!llmDebugMode);
  }

  Future<void> setUseLocalComputeMode(bool value) async {
    if (value && !canUseLocalMock) return;
    if (!value && !hasBleGateway) return;
    useLocalComputeMode = value;
    notifyListeners();
    await _save();
  }

  void _ensureSystemPrompt() {
    final prompt = _systemPromptForTopic(topic);
    final idx = messages.indexWhere((m) => m.role == Role.system);
    if (idx == -1) {
      messages.insert(
        0,
        ChatMessage(
          id: _uuid.v4(),
          role: Role.system,
          content: prompt,
          createdAt: DateTime.now(),
        ),
      );
      return;
    }
    final cur = messages[idx];
    if (cur.content == prompt) return;
    messages[idx] = ChatMessage(
      id: cur.id,
      role: Role.system,
      content: prompt,
      createdAt: DateTime.now(),
    );
  }

  Future<void> _appendAssistantMessage(String content) async {
    messages.add(
      ChatMessage(
        id: _uuid.v4(),
        role: Role.assistant,
        content: content,
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
    await _save();
  }

  Future<void> _appendUserMessage(String content) async {
    messages.add(
      ChatMessage(
        id: _uuid.v4(),
        role: Role.user,
        content: content,
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
    await _save();
  }

  ParsedCommand _parseCommand(String raw) {
    final parts = raw.trim().split(RegExp(r"\s+"));
    final cmd = parts.first.toLowerCase();
    final args = parts.length > 1 ? parts.sublist(1) : const <String>[];
    switch (cmd) {
      case "/help":
        return ParsedCommand(type: CommandType.help);
      case "/topic":
        return ParsedCommand(type: CommandType.topic, args: args);
      case "/reset":
        return ParsedCommand(type: CommandType.reset);
      case "/logpath":
        return ParsedCommand(type: CommandType.logpath);
      default:
        return ParsedCommand(type: CommandType.unknown);
    }
  }

  String _topicUsageText() {
    return "可用 topic：alcohol、medication、memory、mental_state、hypertension、lipids、nutrition\n"
        "目前 topic：${topic.label}";
  }

  Future<void> _handleCommand(String raw) async {
    final parsed = _parseCommand(raw);

    if (parsed.type == CommandType.help) {
      await _appendAssistantMessage(
        "可用指令：\n"
        "/help 顯示指令\n"
        "/topic <酒精|藥物|記憶|心理狀態|高血壓|血脂|營養> 切換策略\n"
        "/reset 清除目前對話\n\n"
        "/logpath 顯示 GeneLLM log 檔路徑\n\n"
        "${_topicUsageText()}\n"
        "GeneLLM：${geneLlmEnabled ? "ON" : "OFF"}（右上角按鈕切換）",
      );
      return;
    }

    if (parsed.type == CommandType.topic) {
      if (parsed.args.isEmpty) {
        await _appendAssistantMessage(_topicUsageText());
        return;
      }
      try {
        topic = ChatTopic.fromInput(parsed.args.first);
        _ensureSystemPrompt();
        await _appendAssistantMessage(
          "已切換 topic：${topic.label}\n"
          "策略：tool=${_currentStrategy.defaultTools.join(",")} ragTopK=${_currentStrategy.ragTopK}",
        );
      } catch (_) {
        await _appendAssistantMessage(
          "未知 topic：${parsed.args.first}\n${_topicUsageText()}",
        );
      }
      return;
    }

    if (parsed.type == CommandType.reset) {
      messages
        ..clear()
        ..add(
          ChatMessage(
            id: _uuid.v4(),
            role: Role.system,
            content: _systemPromptForTopic(topic),
            createdAt: DateTime.now(),
          ),
        );
      await _appendAssistantMessage("對話已重置。");
      return;
    }

    if (parsed.type == CommandType.logpath) {
      final path = await api.getGeneLlmLogPath();
      await _appendAssistantMessage(
        path == null ? "目前平台不支援本地 log 檔。" : "GeneLLM log 路徑：$path",
      );
      return;
    }

    await _appendAssistantMessage("未知指令，輸入 /help 查看可用指令。");
  }

  String _mapTopicForEdge(ChatTopic topic) {
    switch (topic) {
      case ChatTopic.alcohol:
        return "酒精";
      case ChatTopic.medication:
        return "藥物";
      case ChatTopic.memory:
        return "記憶";
      case ChatTopic.mentalState:
        return "心理狀態";
      case ChatTopic.hypertension:
        return "高血壓";
      case ChatTopic.lipids:
        return "血脂";
      case ChatTopic.nutrition:
        return "營養";
    }
  }

  String _formatEdgeStateFullJson(Map<String, dynamic> state) {
    return const JsonEncoder.withIndent("  ").convert(state);
  }

  String _buildEdgeReplyText(_EdgeResult edgeResult) {
    final status = edgeResult.state["status"]?.toString() ?? "unknown";
    final apiResp = edgeResult.state["api_response"];
    String code = "-";
    String query = "-";
    String topicText = "-";
    if (apiResp is Map<String, dynamic>) {
      final c = apiResp["code"];
      if (c != null) code = c.toString();
      final msg = apiResp["Msg"];
      if (msg is Map<String, dynamic>) {
        final rd = msg["response_data"];
        if (rd is Map<String, dynamic>) {
          final q = rd["query"];
          final t = rd["topic"];
          if (q != null) query = q.toString();
          if (t != null) topicText = t.toString();
        }
      }
    }
    return "[EDGE RESULT job=${edgeResult.jobId}]\n"
        "status: $status\n"
        "code: $code\n"
        "query: $query\n"
        "topic: $topicText";
  }

  String _buildBleFailureText(Object error) {
    return "[BLE FAILED]\n"
        "$error\n\n"
        "已改用 cloud fallback。";
  }

  String _buildMockLocalReplyText(Map<String, dynamic> payload) {
    final userId = payload["user_id"]?.toString() ?? "-";
    final query = payload["query"]?.toString() ?? "-";
    final topicText = payload["topic"]?.toString() ?? "-";
    final snpRaw =
        payload["SNP_list"] ?? payload["snp_list"] ?? payload["variants"];
    final snpCount = snpRaw is List ? snpRaw.length : 0;
    return "[LOCAL COMPUTE MOCK]\n"
        "user_id: $userId\n"
        "query: $query\n"
        "topic: $topicText\n"
        "SNP_list: $snpCount items";
  }

  Map<String, dynamic> _effectiveLocalPayloadForMessage({
    required String userQuery,
  }) {
    final raw = localMockPayload;
    final base =
        (raw == null) ? <String, dynamic>{} : Map<String, dynamic>.from(raw);
    base["query"] = userQuery;
    base["topic"] = _mapTopicForEdge(topic);
    return base;
  }

  Future<_EdgeResult?> _tryFetchFromBle(String query) async {
    if (!preferEdgeBleForLlm || bleGateway == null) return null;
    final jobId = _uuid.v4();
    final state = await bleGateway!.runJobAndGetResult(
      jobId: jobId,
      query: query,
      topic: _mapTopicForEdge(topic),
      preferredDeviceId: preferredBleDeviceId,
    );
    final returnedJobId = state["job_id"]?.toString();
    return _EdgeResult(
      jobId: (returnedJobId == null || returnedJobId.isEmpty)
          ? jobId
          : returnedJobId,
      state: state,
    );
  }

  _LlmInputBundle _buildLlmInput({
    required String userQuery,
    _EdgeResult? edgeResult,
  }) {
    final fallbackUserId = (llmUserId == null || llmUserId!.trim().isEmpty)
        ? threadId
        : llmUserId!.trim();
    var query = userQuery;
    var topicText = _mapTopicForEdge(topic);
    var userId = fallbackUserId;
    var variants = <String>[...snpList];
    dynamic yuguard;

    Map<String, dynamic>? asStringMap(dynamic raw) {
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) {
        return raw.map((k, v) => MapEntry(k.toString(), v));
      }
      return null;
    }

    final state = edgeResult?.state;
    if (state != null) {
      final apiResp = asStringMap(state["api_response"]);
      if (apiResp != null) {
        final msg = asStringMap(apiResp["Msg"] ?? apiResp["msg"]);
        if (msg != null) {
          final responseData =
              asStringMap(msg["response_data"] ?? msg["responseData"]);
          if (responseData != null) {
            final q = responseData["query"]?.toString();
            final t = responseData["topic"]?.toString();
            final u = responseData["user_id"]?.toString();
            if (q != null && q.trim().isNotEmpty) query = q.trim();
            if (t != null && t.trim().isNotEmpty) topicText = t.trim();
            if (u != null && u.trim().isNotEmpty) userId = u.trim();

            final snpRaw = responseData["SNP_list"] ??
                responseData["snp_list"] ??
                responseData["variants"];

            if (snpRaw is List) {
              final parsed = snpRaw
                  .map((e) => e?.toString() ?? "")
                  .where((e) => e.trim().isNotEmpty)
                  .toList();
              if (parsed.isNotEmpty) variants = parsed;
              if (llmDebugMode && kDebugMode) {
                debugPrint(
                  "[GeneLLM] extracted variants from response_data: ${parsed.length}",
                );
              }
            }

            yuguard = responseData["yuguard"];
          }
          yuguard ??= msg["yuguard"];
          final msgUserId = msg["user_id"]?.toString();
          if (msgUserId != null && msgUserId.trim().isNotEmpty) {
            userId = msgUserId.trim();
          }
        }
      }
    }

    return _LlmInputBundle(
      userId: userId,
      query: query,
      topic: topicText,
      variants: variants,
      yuguard: yuguard,
    );
  }

  _LlmInputBundle _buildLlmInputFromLocalMock({
    required String fallbackQuery,
    required Map<String, dynamic> payload,
  }) {
    final fallbackUserId = (llmUserId == null || llmUserId!.trim().isEmpty)
        ? threadId
        : llmUserId!.trim();
    final userId = payload["user_id"]?.toString().trim();
    final query = payload["query"]?.toString().trim();
    final topicText = payload["topic"]?.toString().trim();
    final snpRaw =
        payload["SNP_list"] ?? payload["snp_list"] ?? payload["variants"];
    final variants = (snpRaw is List)
        ? snpRaw
            .map((e) => e?.toString() ?? "")
            .where((e) => e.trim().isNotEmpty)
            .toList()
        : <String>[...snpList];
    final yuguard = payload["yuguard"];

    return _LlmInputBundle(
      userId: (userId == null || userId.isEmpty) ? fallbackUserId : userId,
      query: (query == null || query.isEmpty) ? fallbackQuery : query,
      topic: (topicText == null || topicText.isEmpty)
          ? _mapTopicForEdge(topic)
          : topicText,
      variants: variants,
      yuguard: yuguard,
    );
  }

  Future<_LlmReply> _runCloudLlm({
    required String userQuery,
    _EdgeResult? edgeResult,
    _LlmInputBundle? overrideInput,
  }) async {
    final llmInput = overrideInput ??
        _buildLlmInput(
          userQuery: userQuery,
          edgeResult: edgeResult,
        );
    if (llmDebugMode && kDebugMode) {
      debugPrint(
        "[GeneLLM] llm_input topic=${llmInput.topic} variants=${llmInput.variants.length} yuguard=${llmInput.yuguard == null ? "null" : "set"}",
      );
      final previewCount =
          llmInput.variants.length >= 5 ? 5 : llmInput.variants.length;
      debugPrint(
        "[GeneLLM] variants_preview=${llmInput.variants.take(previewCount).toList()}",
      );
    }
    final result = await api.askLlm(
      userId: llmInput.userId,
      aggregatedQuery: llmInput.query,
      topic: llmInput.topic,
      variants: llmInput.variants,
      yuguard: llmInput.yuguard,
      debugMode: llmDebugMode,
    );
    return _LlmReply(
      answer: result.answer,
      source: "CLOUD",
      requestLog: {
        "url": result.url,
        "headers": result.headers,
        "status": result.statusCode,
        "payload": result.payload,
      },
    );
  }

  void _clearTypingBubbles() {
    messages.removeWhere((m) => m.role == Role.assistant && m.isTyping);
  }

  String _buildLlmRequestSummary(Map<String, dynamic> requestLog) {
    final url = requestLog["url"]?.toString() ?? "-";
    final status = requestLog["status"]?.toString() ?? "-";
    final payloadRaw = requestLog["payload"];
    final payload = payloadRaw is Map ? payloadRaw.cast<String, dynamic>() : {};
    final userId = payload["user_id"]?.toString() ?? "-";
    final query = payload["query"]?.toString() ?? "-";
    final topicText = payload["topic"]?.toString() ?? "-";
    final variantsRaw =
        payload["SNP_list"] ?? payload["snp_list"] ?? payload["variants"];
    final snpListText = variantsRaw is List
        ? const JsonEncoder.withIndent("  ").convert(variantsRaw)
        : "[]";
    final yuguardState = payload["yuguard"] == null ? "null" : "set";
    return "[LLM REQUEST]\n"
        "status: $status\n"
        "url: $url\n"
        "user_id: $userId\n"
        "query: $query\n"
        "topic: $topicText\n"
        "SNP_list: $snpListText\n"
        "yuguard: $yuguardState";
  }

  void _upsertDebugMessage({
    required String typingId,
    required String content,
    required String kind,
    required String fullJson,
  }) {
    if (!llmDebugMode) return;
    final idx = messages.indexWhere((m) => m.id == typingId);
    final msg = ChatMessage(
      id: idx == -1 ? _uuid.v4() : typingId,
      role: Role.assistant,
      content: content,
      createdAt: DateTime.now(),
      isTyping: false,
      meta: {
        "kind": kind,
        "debug": true,
        "full_json": fullJson,
      },
    );
    if (idx == -1) {
      messages.add(msg);
    } else {
      messages[idx] = msg;
    }
  }

  void _appendLlmRequestDebug(Map<String, dynamic>? requestLog) {
    if (!llmDebugMode || requestLog == null) return;
    messages.add(
      ChatMessage(
        id: _uuid.v4(),
        role: Role.assistant,
        content: _buildLlmRequestSummary(requestLog),
        createdAt: DateTime.now(),
        meta: {
          "kind": "llm_request",
          "debug": true,
          "full_json": const JsonEncoder.withIndent("  ").convert(requestLog),
        },
      ),
    );
  }

  String _formatFinalAnswer(_LlmReply reply) {
    final answer =
        reply.answer.trim().isEmpty ? "(empty response)" : reply.answer;
    if (!llmDebugMode) return answer;
    final sourceTag = reply.jobId == null || reply.jobId!.isEmpty
        ? "[${reply.source}]"
        : "[${reply.source} job=${reply.jobId}]";
    return "$sourceTag $answer";
  }

  bool _isGreeting(String lower) {
    const keywords = [
      "你好",
      "嗨",
      "hello",
      "hi",
      "早安",
      "午安",
      "晚安",
      "哈囉",
    ];
    return keywords.any(lower.contains);
  }

  Future<void> _handleChatOnlyMessage(String query) async {
    if (!llmDebugMode) return;
    final lower = query.toLowerCase();
    final content = _isGreeting(lower)
        ? "你好，我是 GeneApp 助理。目前是 ChatOnly 模式，你可以開啟 GeneLLM 使用 edge + LLM 流程。"
        : "已收到你的訊息：$query\n"
            "目前是 ChatOnly（不使用 LLM）。若要啟用模型回覆，請開啟 GeneLLM。";
    messages.add(
      ChatMessage(
        id: _uuid.v4(),
        role: Role.assistant,
        content: content,
        createdAt: DateTime.now(),
        meta: {
          "kind": "chat_only",
          "debug": true,
        },
      ),
    );
    notifyListeners();
    await _save();
  }

  Future<void> sendUserMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    await _appendUserMessage(trimmed);

    if (trimmed.startsWith("/")) {
      await _handleCommand(trimmed);
      return;
    }

    if (!geneLlmEnabled) {
      await _handleChatOnlyMessage(trimmed);
      return;
    }

    // typing bubble
    final typingId = _uuid.v4();
    String? llmTypingId;
    messages.add(ChatMessage(
      id: typingId,
      role: Role.assistant,
      content: "…",
      createdAt: DateTime.now(),
      isTyping: true,
    ));

    notifyListeners();
    await _save();

    try {
      if (useLocalComputeMode && localMockPayload != null) {
        final effectivePayload = _effectiveLocalPayloadForMessage(
          userQuery: trimmed,
        );
        final llmInput = _buildLlmInputFromLocalMock(
          fallbackQuery: trimmed,
          payload: effectivePayload,
        );
        _upsertDebugMessage(
          typingId: typingId,
          content: _buildMockLocalReplyText(effectivePayload),
          kind: "edge_result",
          fullJson:
              const JsonEncoder.withIndent("  ").convert(effectivePayload),
        );
        if (llmDebugMode) {
          llmTypingId = _uuid.v4();
          messages.add(
            ChatMessage(
              id: llmTypingId,
              role: Role.assistant,
              content: "…",
              createdAt: DateTime.now(),
              isTyping: true,
            ),
          );
        }
        notifyListeners();
        await _save();

        final cloudReply = await _runCloudLlm(
          userQuery: trimmed,
          edgeResult: null,
          overrideInput: llmInput,
        );
        final reply = _LlmReply(
          answer: cloudReply.answer,
          source: "CLOUD",
          jobId: "LOCAL_MOCK",
          requestLog: cloudReply.requestLog,
        );

        _appendLlmRequestDebug(reply.requestLog);
        final finalAnswer = _formatFinalAnswer(reply);
        _clearTypingBubbles();
        messages.add(
          ChatMessage(
            id: _uuid.v4(),
            role: Role.assistant,
            content: finalAnswer,
            createdAt: DateTime.now(),
          ),
        );
        notifyListeners();
        await _save();
        return;
      }

      _EdgeResult? edgeResult;
      try {
        edgeResult = await _tryFetchFromBle(trimmed);
      } catch (e) {
        _upsertDebugMessage(
          typingId: typingId,
          content: _buildBleFailureText(e),
          kind: "ble_error",
          fullJson: const JsonEncoder.withIndent("  ").convert({
            "error": "$e",
            "fallback": "cloud",
          }),
        );
        notifyListeners();
        await _save();
        edgeResult = null;
      }

      if (edgeResult != null) {
        _upsertDebugMessage(
          typingId: typingId,
          content: _buildEdgeReplyText(edgeResult),
          kind: "edge_result",
          fullJson: _formatEdgeStateFullJson(edgeResult.state),
        );
        if (llmDebugMode) {
          llmTypingId = _uuid.v4();
          messages.add(
            ChatMessage(
              id: llmTypingId,
              role: Role.assistant,
              content: "…",
              createdAt: DateTime.now(),
              isTyping: true,
            ),
          );
        }
        notifyListeners();
        await _save();

        final cloudReply = await _runCloudLlm(
          userQuery: trimmed,
          edgeResult: edgeResult,
        );
        final reply = _LlmReply(
          answer: cloudReply.answer,
          source: "CLOUD",
          jobId: edgeResult.jobId,
          requestLog: cloudReply.requestLog,
        );

        _appendLlmRequestDebug(reply.requestLog);
        final finalAnswer = _formatFinalAnswer(reply);
        _clearTypingBubbles();
        messages.add(
          ChatMessage(
            id: _uuid.v4(),
            role: Role.assistant,
            content: finalAnswer,
            createdAt: DateTime.now(),
          ),
        );
        notifyListeners();
        await _save();
        return;
      }

      if (!allowCloudFallbackWhenBleFails) {
        throw Exception("BLE 未成功取得結果，且目前關閉 cloud fallback。");
      }

      final reply = await (() async {
        return _runCloudLlm(
          userQuery: trimmed,
          edgeResult: null,
        );
      })();

      _appendLlmRequestDebug(reply.requestLog);
      final finalAnswer = _formatFinalAnswer(reply);
      _clearTypingBubbles();
      messages.add(ChatMessage(
        id: _uuid.v4(),
        role: Role.assistant,
        content: finalAnswer,
        createdAt: DateTime.now(),
      ));

      notifyListeners();
      await _save();
    } catch (e) {
      _clearTypingBubbles();
      messages.add(
        ChatMessage(
          id: _uuid.v4(),
          role: Role.assistant,
          content: "❌ 發生錯誤：$e",
          createdAt: DateTime.now(),
        ),
      );
      notifyListeners();
      await _save();
    }
  }
}
