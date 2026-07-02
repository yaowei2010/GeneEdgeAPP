import "package:flutter/material.dart";
import "package:flutter_markdown/flutter_markdown.dart";
import "package:provider/provider.dart";
import "package:speech_to_text/speech_recognition_result.dart";
import "package:speech_to_text/speech_to_text.dart";
import "chat_controller.dart";
import "models.dart";

class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({super.key});

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _speech = SpeechToText();
  bool _speechReady = false;
  bool _isListening = false;
  bool _panelCollapsed = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    _speechReady = await _speech.initialize();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _toggleVoiceInput() async {
    if (_isListening) {
      await _stopVoiceInput();
    } else {
      await _startVoiceInput();
    }
  }

  Future<bool> _ensureSpeechReady() async {
    if (!_speechReady) {
      await _initSpeech();
      if (!_speechReady) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("語音辨識初始化失敗，請確認麥克風權限。")),
        );
        return false;
      }
    }
    return true;
  }

  Future<void> _startVoiceInput() async {
    final ok = await _ensureSpeechReady();
    if (!ok || _isListening) return;

    _textCtrl.clear();
    _textCtrl.selection = const TextSelection.collapsed(offset: 0);

    await _speech.listen(
      localeId: "zh_TW",
      onResult: _onSpeechResult,
      listenOptions: SpeechListenOptions(
        partialResults: true,
      ),
    );
    if (!mounted) return;
    setState(() => _isListening = true);
  }

  Future<void> _stopVoiceInput() async {
    if (_isListening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() => _isListening = false);
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    _textCtrl.text = result.recognizedWords;
    _textCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _textCtrl.text.length),
    );
    if (result.finalResult && mounted) {
      setState(() => _isListening = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _openBlePicker() async {
    final c = context.read<ChatController>();
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text("選擇藍牙裝置"),
          content: SizedBox(
            width: 360,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: c.scanBleDevices(),
              builder: (_, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 80,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Text("掃描失敗：${snapshot.error}");
                }

                final rows = snapshot.data ?? const [];
                if (rows.isEmpty) {
                  return const Text("找不到可用 BLE 裝置");
                }

                return SizedBox(
                  height: 260,
                  child: ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final row = rows[i];
                      final id = row["id"]?.toString() ?? "";
                      final name = row["name"]?.toString() ?? "(no name)";
                      final rssi = row["rssi"]?.toString() ?? "-";
                      return ListTile(
                        title: Text(name),
                        subtitle: Text("id=$id  RSSI=$rssi"),
                        onTap: () async {
                          await c.setPreferredBleDevice(
                            id: id,
                            label: "$name ($id)",
                          );
                          if (!mounted) return;
                          Navigator.of(dialogCtx).pop();
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await c.setPreferredBleDevice(id: null, label: null);
                if (!mounted) return;
                Navigator.of(dialogCtx).pop();
              },
              child: const Text("使用自動偵測"),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text("關閉"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ChatController>();
    _scrollToBottom();

    final visible = c.messages.where((m) => m.role != Role.system).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("GeneEdgeRobot"),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFEFF5FB), Color(0xFFF7FAFD)],
            ),
          ),
          child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFDFEFF),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFCEE0EE)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14335C7A),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          "GeneEdge Control Panel",
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF4A6980),
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          _panelCollapsed
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_up,
                        ),
                        tooltip: _panelCollapsed ? "展開控制面板" : "收合控制面板",
                        onPressed: () {
                          setState(() => _panelCollapsed = !_panelCollapsed);
                        },
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    child: _panelCollapsed
                        ? const SizedBox.shrink()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (c.hasBleGateway || c.canUseLocalMock)
                                    SegmentedButton<bool>(
                                      segments: [
                                        if (c.hasBleGateway)
                                          const ButtonSegment<bool>(
                                            value: false,
                                            label: Text("BLE"),
                                            icon: Icon(Icons.bluetooth),
                                          ),
                                        if (c.canUseLocalMock)
                                          const ButtonSegment<bool>(
                                            value: true,
                                            label: Text("In APP"),
                                            icon: Icon(Icons.memory),
                                          ),
                                      ],
                                      selected: {c.useLocalComputeMode},
                                      onSelectionChanged: (s) async {
                                        final next = s.first;
                                        await c.setUseLocalComputeMode(next);
                                      },
                                    ),
                                  c.geneLlmEnabled
                                      ? FilledButton(
                                          onPressed: () => c.toggleGeneLlm(),
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFF0B5D7A),
                                          ),
                                          child: const Text("GeneLLM"),
                                        )
                                      : OutlinedButton(
                                          onPressed: () => c.toggleGeneLlm(),
                                          child: const Text("GeneLLM"),
                                        ),
                                  if (c.hasBleGateway && !c.useLocalComputeMode)
                                    OutlinedButton.icon(
                                      onPressed: _openBlePicker,
                                      icon:
                                          const Icon(Icons.bluetooth_searching),
                                      label: const Text("BLE"),
                                    ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text("Topic: "),
                                      DropdownButton<ChatTopic>(
                                        value: c.topic,
                                        items: ChatController.selectableTopics
                                            .map(
                                              (t) =>
                                                  DropdownMenuItem<ChatTopic>(
                                                value: t,
                                                child: Text(t.label),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (next) async {
                                          if (next == null) return;
                                          await c.setTopic(next);
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Chip(
                                    avatar: Icon(
                                      Icons.memory_rounded,
                                      size: 16,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                    label: Text(
                                      "Mode: ${c.geneLlmEnabled ? "GeneLLM ON" : "Chat Only"} / ${c.computeModeLabel}",
                                    ),
                                  ),
                                  if (c.hasBleGateway && !c.useLocalComputeMode)
                                    Chip(
                                      avatar: const Icon(
                                        Icons.devices_rounded,
                                        size: 16,
                                        color: Color(0xFF0B5D7A),
                                      ),
                                      label: Text(
                                          "Device: ${c.bleDeviceDisplayName}"),
                                    ),
                                ],
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(vertical: 10),
                itemCount: visible.length,
                itemBuilder: (_, i) => _Bubble(msg: visible[i]),
              ),
            ),
            _Composer(
              controller: _textCtrl,
              isListening: _isListening,
              onSend: () async {
                final text = _textCtrl.text;
                _textCtrl.clear();
                FocusManager.instance.primaryFocus?.unfocus();
                await c.sendUserMessage(text);
              },
              onMic: _toggleVoiceInput,
              onMicStart: _startVoiceInput,
              onMicEnd: _stopVoiceInput,
            )
          ],
        ),
      ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage msg;
  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == Role.user;
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isUser ? const Color(0xFFDDEFFC) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isUser ? const Color(0xFFB8D7EF) : const Color(0xFFD8E5EF),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x10335C7A),
                blurRadius: 8,
                offset: Offset(0, 3),
              )
            ],
          ),
          child: msg.isTyping
              ? const Text(
                  "AI 正在輸入…",
                  style: TextStyle(fontSize: 15, height: 1.35),
                )
              : _BubbleContent(msg: msg),
        ),
      ),
    );
  }
}

class _BubbleContent extends StatelessWidget {
  final ChatMessage msg;
  const _BubbleContent({required this.msg});

  @override
  Widget build(BuildContext context) {
    final kind = msg.meta?["kind"]?.toString();
    if (kind == "edge_result") {
      final fullJson = msg.meta?["full_json"]?.toString() ?? "";
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            msg.content,
            style: const TextStyle(fontSize: 15, height: 1.35),
          ),
          const SizedBox(height: 6),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text(
              "完整 JSON",
              style: TextStyle(fontSize: 13),
            ),
            children: [
              SelectableText(
                fullJson,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  fontFamily: "monospace",
                ),
              ),
            ],
          ),
        ],
      );
    }
    if (kind == "llm_request") {
      final fullJson = msg.meta?["full_json"]?.toString() ?? "";
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            msg.content,
            style: const TextStyle(fontSize: 14, height: 1.3),
          ),
          const SizedBox(height: 6),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text(
              "Request JSON",
              style: TextStyle(fontSize: 13),
            ),
            children: [
              SelectableText(
                fullJson,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  fontFamily: "monospace",
                ),
              ),
            ],
          ),
        ],
      );
    }
    if (msg.role == Role.assistant) {
      return MarkdownBody(
        data: msg.content,
        selectable: true,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: const TextStyle(fontSize: 15, height: 1.35),
          code: const TextStyle(fontFamily: "monospace", fontSize: 13),
          blockquote: const TextStyle(fontSize: 14, height: 1.35),
        ),
      );
    }
    return Text(msg.content,
        style: const TextStyle(fontSize: 15, height: 1.35));
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onMic;
  final VoidCallback onMicStart;
  final VoidCallback onMicEnd;
  final bool isListening;
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onMic,
    required this.onMicStart,
    required this.onMicEnd,
    required this.isListening,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFDFEFF),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14335C7A),
                blurRadius: 12,
                offset: Offset(0, 4),
              )
            ],
            border: Border.all(color: const Color(0xFFCEE0EE)),
          ),
          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  onSubmitted: (_) => onSend(),
                  decoration: const InputDecoration(
                    hintText: "輸入訊息…",
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onLongPressStart: (_) => onMicStart(),
                onLongPressEnd: (_) => onMicEnd(),
                child: IconButton(
                  icon: Icon(isListening ? Icons.mic : Icons.mic_none),
                  color: isListening
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  tooltip: "長按說話，放開停止（點擊切換）",
                  onPressed: onMic,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: onSend,
              )
            ],
          ),
        ),
      ),
    );
  }
}
