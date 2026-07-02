import "package:flutter/material.dart";
import "package:flutter_markdown/flutter_markdown.dart";
import "package:provider/provider.dart";
import "package:speech_to_text/speech_recognition_result.dart";
import "package:speech_to_text/speech_to_text.dart";
import "chat_controller.dart";
import "models.dart";

class ChatRoomPage extends StatefulWidget {
  final VoidCallback? onLogout;

  const ChatRoomPage({super.key, this.onLogout});

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _speech = SpeechToText();
  bool _speechReady = false;
  bool _isListening = false;
  bool _panelCollapsed = true;

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
                          if (!dialogCtx.mounted) return;
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
                if (!dialogCtx.mounted) return;
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

  Future<void> _openTopicPicker() async {
    final controller = context.read<ChatController>();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFDFEFF),
      builder: (sheetCtx) {
        final sheetHeight = MediaQuery.sizeOf(sheetCtx).height * 0.72;
        return SizedBox(
          height: sheetHeight,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "選擇健康主題",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF102F3F),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  "GeneEdge 會依照主題調整回答策略",
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF607889),
                  ),
                ),
                const SizedBox(height: 16),
                _TopicIconGrid(
                  controller: controller,
                  topicFor: _topicPresentation,
                  onSelected: (topic) {
                    Navigator.of(sheetCtx).pop();
                    controller.setTopic(topic);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  TopicPresentation _topicPresentation(ChatTopic topic) {
    switch (topic) {
      case ChatTopic.alcohol:
        return const TopicPresentation(
          icon: Icons.local_bar_rounded,
          label: "酒精代謝",
          subtitle: "飲酒風險",
          color: Color(0xFF0B6E69),
        );
      case ChatTopic.medication:
        return const TopicPresentation(
          icon: Icons.medication_rounded,
          label: "藥物反應",
          subtitle: "用藥提醒",
          color: Color(0xFF315D9A),
        );
      case ChatTopic.memory:
        return const TopicPresentation(
          icon: Icons.psychology_alt_rounded,
          label: "記憶認知",
          subtitle: "認知照護",
          color: Color(0xFF7A4E9D),
        );
      case ChatTopic.mentalState:
        return const TopicPresentation(
          icon: Icons.self_improvement_rounded,
          label: "心理狀態",
          subtitle: "情緒支持",
          color: Color(0xFFB65F2B),
        );
      case ChatTopic.hypertension:
        return const TopicPresentation(
          icon: Icons.monitor_heart_rounded,
          label: "高血壓",
          subtitle: "血壓管理",
          color: Color(0xFFC14444),
        );
      case ChatTopic.lipids:
        return const TopicPresentation(
          icon: Icons.bloodtype_rounded,
          label: "血脂管理",
          subtitle: "代謝健康",
          color: Color(0xFF4F6F2A),
        );
      case ChatTopic.nutrition:
        return const TopicPresentation(
          icon: Icons.restaurant_rounded,
          label: "營養建議",
          subtitle: "飲食規劃",
          color: Color(0xFF2E7D48),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ChatController>();
    _scrollToBottom();

    final visible = c.messages.where((m) {
      if (m.role == Role.system) return false;
      final isDebugMessage = (m.meta?["debug"] as bool?) ?? false;
      final kind = m.meta?["kind"]?.toString();
      final isDiagnosticMessage = isDebugMessage ||
          kind == "edge_result" ||
          kind == "llm_request" ||
          kind == "chat_only";
      if (isDiagnosticMessage && !c.llmDebugMode) return false;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) {
            return IconButton(
              icon: const Icon(Icons.menu_rounded),
              tooltip: "開啟選單",
              onPressed: () => Scaffold.of(context).openDrawer(),
            );
          },
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("GeneEdge"),
            Text(
              "Personal health intelligence",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF5F7585),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _TopicBadge(
              item: _topicPresentation(c.topic),
              onTap: _openTopicPicker,
            ),
          ),
        ],
      ),
      drawer: _AppDrawer(
        controller: c,
        topicFor: _topicPresentation,
        onChooseTopic: () {
          Navigator.of(context).pop();
          _openTopicPicker();
        },
        onLogout: widget.onLogout == null
            ? null
            : () {
                Navigator.of(context).pop();
                widget.onLogout!();
              },
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
              _ExperiencePanel(
                controller: c,
                collapsed: _panelCollapsed,
                topicFor: _topicPresentation,
                onToggleCollapsed: () {
                  setState(() => _panelCollapsed = !_panelCollapsed);
                },
                onOpenTopicPicker: _openTopicPicker,
                onOpenBlePicker: _openBlePicker,
              ),
              Expanded(
                child: visible.isEmpty
                    ? _EmptyConversation(
                        item: _topicPresentation(c.topic),
                        onChooseTopic: _openTopicPicker,
                      )
                    : ListView.builder(
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

class TopicPresentation {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;

  const TopicPresentation({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
  });
}

class _TopicBadge extends StatelessWidget {
  final TopicPresentation item;
  final VoidCallback onTap;

  const _TopicBadge({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: item.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 36, maxWidth: 156),
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: item.color.withValues(alpha: 0.32)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.icon, size: 17, color: item.color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF173747),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.expand_more_rounded,
                  size: 17,
                  color: item.color,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExperiencePanel extends StatelessWidget {
  final ChatController controller;
  final bool collapsed;
  final TopicPresentation Function(ChatTopic topic) topicFor;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onOpenTopicPicker;
  final VoidCallback onOpenBlePicker;

  const _ExperiencePanel({
    required this.controller,
    required this.collapsed,
    required this.topicFor,
    required this.onToggleCollapsed,
    required this.onOpenTopicPicker,
    required this.onOpenBlePicker,
  });

  @override
  Widget build(BuildContext context) {
    final active = topicFor(controller.topic);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFEFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD7E4EC)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14335C7A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: active.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(active.icon, color: active.color, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active.label,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF102F3F),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      controller.geneLlmEnabled
                          ? "AI 已就緒，輸入問題即可開始"
                          : "請開啟 GeneLLM 後開始詢問",
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF607889),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onOpenTopicPicker,
                icon: const Icon(Icons.grid_view_rounded, size: 18),
                label: const Text("切換"),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  collapsed
                      ? Icons.tune_rounded
                      : Icons.keyboard_arrow_up_rounded,
                ),
                tooltip: collapsed ? "開啟設定" : "收合設定",
                onPressed: onToggleCollapsed,
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: collapsed
                ? const SizedBox.shrink()
                : _OperationsPanel(
                    controller: controller,
                    onOpenBlePicker: onOpenBlePicker,
                  ),
          ),
        ],
      ),
    );
  }
}

class _TopicIconGrid extends StatelessWidget {
  final ChatController controller;
  final TopicPresentation Function(ChatTopic topic) topicFor;
  final ValueChanged<ChatTopic>? onSelected;

  const _TopicIconGrid({
    required this.controller,
    required this.topicFor,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 520 ? 4 : 2;
        final gap = 8.0;
        final width = (constraints.maxWidth - (gap * (columns - 1))) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: ChatController.selectableTopics.map((topic) {
            final item = topicFor(topic);
            final selected = controller.topic == topic;
            return SizedBox(
              width: width,
              child: _TopicTile(
                item: item,
                selected: selected,
                onTap: () {
                  if (onSelected != null) {
                    onSelected!(topic);
                    return;
                  }
                  controller.setTopic(topic);
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _TopicTile extends StatelessWidget {
  final TopicPresentation item;
  final bool selected;
  final VoidCallback onTap;

  const _TopicTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = item.color;
    return Material(
      color: selected ? color.withValues(alpha: 0.10) : const Color(0xFFF6FAFC),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 74,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : const Color(0xFFDDE8EF),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: selected ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(item.icon, size: 20, color: color),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.15,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w700,
                        color: const Color(0xFF173747),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.1,
                        color: Color(0xFF6B8190),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: color, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _OperationsPanel extends StatelessWidget {
  final ChatController controller;
  final VoidCallback onOpenBlePicker;

  const _OperationsPanel({
    required this.controller,
    required this.onOpenBlePicker,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1, color: Color(0xFFE1EBF1)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (controller.hasBleGateway || controller.canUseLocalMock)
                SegmentedButton<bool>(
                  segments: [
                    if (controller.hasBleGateway)
                      const ButtonSegment<bool>(
                        value: false,
                        label: Text("BLE"),
                        icon: Icon(Icons.bluetooth_rounded),
                      ),
                    if (controller.canUseLocalMock)
                      const ButtonSegment<bool>(
                        value: true,
                        label: Text("In App"),
                        icon: Icon(Icons.inventory_2_rounded),
                      ),
                  ],
                  selected: {controller.useLocalComputeMode},
                  onSelectionChanged: (s) {
                    controller.setUseLocalComputeMode(s.first);
                  },
                ),
              _ModeButton(
                active: controller.geneLlmEnabled,
                icon: Icons.auto_awesome_rounded,
                label: "GeneLLM",
                activeColor: const Color(0xFF0B5D7A),
                onTap: controller.toggleGeneLlm,
              ),
              _ModeButton(
                active: controller.llmDebugMode,
                icon: Icons.bug_report_rounded,
                label: "Debug",
                activeColor: const Color(0xFF5E4A7D),
                onTap: controller.toggleLlmDebugMode,
              ),
              if (controller.hasBleGateway && !controller.useLocalComputeMode)
                OutlinedButton.icon(
                  onPressed: onOpenBlePicker,
                  icon: const Icon(Icons.bluetooth_searching_rounded),
                  label: const Text("裝置"),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill(
                icon: Icons.memory_rounded,
                label:
                    "${controller.geneLlmEnabled ? "LLM ON" : "LLM OFF"} / ${controller.computeModeLabel}",
              ),
              _StatusPill(
                icon: controller.llmDebugMode
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                label: controller.llmDebugMode ? "Debug ON" : "Debug OFF",
              ),
              if (controller.hasBleGateway && !controller.useLocalComputeMode)
                _StatusPill(
                  icon: Icons.devices_rounded,
                  label: controller.bleDeviceDisplayName,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final bool active;
  final IconData icon;
  final String label;
  final Color activeColor;
  final VoidCallback onTap;

  const _ModeButton({
    required this.active,
    required this.icon,
    required this.label,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (active) {
      return FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(backgroundColor: activeColor),
        icon: Icon(icon),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatusPill({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F8FB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE8EF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF486779)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF486779),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppDrawer extends StatelessWidget {
  final ChatController controller;
  final TopicPresentation Function(ChatTopic topic) topicFor;
  final VoidCallback onChooseTopic;
  final VoidCallback? onLogout;

  const _AppDrawer({
    required this.controller,
    required this.topicFor,
    required this.onChooseTopic,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final active = topicFor(controller.topic);
    return Drawer(
      backgroundColor: const Color(0xFFFDFEFF),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x18335C7A),
                          blurRadius: 12,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset("icon.jpeg", fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "GeneEdge",
                          style: TextStyle(
                            fontSize: 19,
                            height: 1.1,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF102F3F),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          "NCKU pilot access",
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF607889),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: active.color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: active.color.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(active.icon, color: active.color, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Current topic",
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF607889),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            active.label,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Color(0xFF102F3F),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _DrawerAction(
                icon: Icons.grid_view_rounded,
                title: "Switch topic",
                subtitle: "Choose another health scenario",
                onTap: onChooseTopic,
              ),
              _DrawerAction(
                icon: Icons.auto_awesome_rounded,
                title: controller.geneLlmEnabled ? "GeneLLM on" : "GeneLLM off",
                subtitle: "Tap to toggle LLM responses",
                onTap: controller.toggleGeneLlm,
              ),
              _DrawerAction(
                icon: Icons.bug_report_rounded,
                title: controller.llmDebugMode ? "Debug on" : "Debug off",
                subtitle: "Show or hide technical diagnostics",
                onTap: controller.toggleLlmDebugMode,
              ),
              if (controller.hasBleGateway && !controller.useLocalComputeMode)
                _DrawerAction(
                  icon: Icons.devices_rounded,
                  title: "BLE device",
                  subtitle: controller.bleDeviceDisplayName,
                  onTap: null,
                ),
              const Spacer(),
              if (onLogout != null)
                OutlinedButton.icon(
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text("Log out"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF8F3D3D),
                    side: const BorderSide(color: Color(0xFFE7CACA)),
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                "© 2026 National Cheng Kung University (NCKU), Taiwan.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  height: 1.2,
                  color: Color(0xFF8EA1AD),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _DrawerAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFFF5F9FB),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFF0B5D7A), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF102F3F),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF607889),
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF8EA1AD),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  final TopicPresentation item;
  final VoidCallback onChooseTopic;

  const _EmptyConversation({
    required this.item,
    required this.onChooseTopic,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 300;
        final iconSize = compact ? 58.0 : 78.0;
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  28,
                  compact ? 8 : 12,
                  28,
                  compact ? 10 : 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          width: iconSize,
                          height: iconSize,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF4F6),
                            borderRadius:
                                BorderRadius.circular(compact ? 18 : 22),
                            border: Border.all(
                              color: item.color.withValues(alpha: 0.20),
                            ),
                          ),
                          child: Icon(
                            Icons.smart_toy_rounded,
                            color: item.color,
                            size: compact ? 31 : 40,
                          ),
                        ),
                        Container(
                          width: compact ? 24 : 30,
                          height: compact ? 24 : 30,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: item.color.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Icon(
                            item.icon,
                            color: item.color,
                            size: compact ? 15 : 18,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 10 : 18),
                    const Text(
                      "我是 GeneEdge 助理",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF102F3F),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: item.color,
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 10),
                      const Text(
                        "選擇主題後，直接輸入你的情境問題，我會依照目前狀態與基因資料協助整理風險與建議。",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: Color(0xFF607889),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _ExamplePromptCard(color: item.color),
                    ],
                    SizedBox(height: compact ? 10 : 18),
                    OutlinedButton.icon(
                      onPressed: onChooseTopic,
                      icon: const Icon(Icons.grid_view_rounded),
                      label: const Text("切換主題"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ExamplePromptCard extends StatelessWidget {
  final Color color;

  const _ExamplePromptCard({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F335C7A),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_rounded, color: color, size: 18),
              const SizedBox(width: 6),
              const Text(
                "範例提問",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF173747),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            "請問我現在的狀態可以喝混酒嗎？",
            style: TextStyle(
              fontSize: 15,
              height: 1.35,
              fontWeight: FontWeight.w700,
              color: Color(0xFF102F3F),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "也可以描述飲酒頻率、最近身體狀況或正在服用的藥物。",
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: Color(0xFF607889),
            ),
          ),
        ],
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
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
                        hintText: "輸入你的健康問題…",
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
            const SizedBox(height: 5),
            const Text(
              "© 2026 National Cheng Kung University (NCKU), Taiwan. All rights reserved.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                height: 1,
                color: Color(0xFF8EA1AD),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
