import 'dart:async';

import 'package:flutter/material.dart';

import 'bluemagpie_tts.dart';

class BlueMagpiePocPage extends StatefulWidget {
  const BlueMagpiePocPage({super.key, required this.tts});

  final BlueMagpieTts tts;

  @override
  State<BlueMagpiePocPage> createState() => _BlueMagpiePocPageState();
}

class _BlueMagpiePocPageState extends State<BlueMagpiePocPage> {
  static const _smokeText = '今天天氣真好，我們一起去散步吧。';

  late final TextEditingController _textController =
      TextEditingController(text: _smokeText);
  BlueMagpieBackend _backend = BlueMagpieBackend.cpu;
  bool _running = false;
  String _status = '尚未測試';
  String _details = '模型只會從 App 私有目錄讀取，測試過程不需要網路。';
  String? _activeRequestId;

  @override
  void dispose() {
    final requestId = _activeRequestId;
    if (requestId != null) unawaited(_ignoreErrors(widget.tts.cancel(requestId)));
    unawaited(_ignoreErrors(widget.tts.release()));
    _textController.dispose();
    super.dispose();
  }

  Future<void> _ignoreErrors(Future<void> operation) async {
    try {
      await operation;
    } on Object {
      // dispose cannot present an error; native cleanup remains best effort.
    }
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _status = '檢查手機環境…';
      _details = '';
    });

    try {
      final probe = await widget.tts.probe();
      if (!probe.available) {
        final code = probe.errorCode ?? BlueMagpieErrorCode.runtimeMissing;
        _showFailure(code, '此 APK 尚未編入藍鵲 runtime。');
        return;
      }

      setState(() => _status = '驗證模型…');
      final validation = await widget.tts.validateModels();
      if (validation.state != BlueMagpieState.ready) {
        final error = validation.models
            .map((model) => model.errorCode)
            .whereType<BlueMagpieErrorCode>()
            .firstOrNull;
        _showFailure(
          error ?? BlueMagpieErrorCode.modelMissing,
          '請先將 Barbet 與 AudioVAE GGUF 安裝到 App 私有模型目錄。',
        );
        return;
      }

      setState(() => _status = '載入模型…');
      final initialized = await widget.tts.initialize(backend: _backend);
      final requestId = 'poc-${DateTime.now().microsecondsSinceEpoch}';
      _activeRequestId = requestId;

      setState(() => _status = '產生中文語音…');
      final result = await widget.tts.synthesize(
        requestId: requestId,
        text: _textController.text,
      );
      await widget.tts.play(result.wavToken);
      _activeRequestId = null;

      if (!mounted) return;
      setState(() {
        _status = '完成，手機正在播放';
        _details = '${initialized.backend == BlueMagpieBackend.cpu ? 'CPU' : 'Vulkan'} · '
            '${result.sampleRate} Hz · ${(result.durationMs / 1000).toStringAsFixed(1)} 秒 · '
            '合成 ${result.elapsedMs} ms · 首音 ${result.firstAudioMs} ms';
      });
    } on BlueMagpieTtsException catch (error) {
      _showFailure(error.code, error.safeMessage);
    } on Object {
      _showFailure(
        BlueMagpieErrorCode.internalError,
        '測試未完成，請查看 Android debug log。',
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _showFailure(BlueMagpieErrorCode code, String message) {
    if (!mounted) return;
    setState(() {
      _status = '無法執行：${code.wireName}';
      _details = message;
    });
  }

  Future<void> _cancel() async {
    final requestId = _activeRequestId;
    if (requestId == null) return;
    await widget.tts.cancel(requestId);
    _activeRequestId = null;
    if (!mounted) return;
    setState(() {
      _running = false;
      _status = '已停止';
      _details = '未完成的 WAV 已要求 native 層清除。';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('台灣藍鵲 TTS 手機測試')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              '輸入中文文字後，模型會直接在 Android 手機上產生 WAV 並播放。',
              style: TextStyle(fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('bluemagpie-text-input'),
              controller: _textController,
              enabled: !_running,
              minLines: 3,
              maxLines: 6,
              maxLength: BlueMagpieTts.maxTextUnicodeScalars,
              decoration: const InputDecoration(
                labelText: '要朗讀的中文文字',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<BlueMagpieBackend>(
              segments: const [
                ButtonSegment(value: BlueMagpieBackend.cpu, label: Text('CPU')),
                ButtonSegment(
                  value: BlueMagpieBackend.vulkan,
                  label: Text('Vulkan'),
                ),
              ],
              selected: {_backend},
              onSelectionChanged: _running
                  ? null
                  : (selection) => setState(() => _backend = selection.single),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _running ? null : _run,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('合成並播放'),
            ),
            if (_running)
              TextButton.icon(
                onPressed: _activeRequestId == null ? null : _cancel,
                icon: const Icon(Icons.stop_rounded),
                label: const Text('停止'),
              ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _status,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_details.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(_details),
                    ],
                    if (_running) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '研究版限制：僅 Android ARM64 debug build；模型約 2.4 GB，首次載入與合成可能需要較長時間。',
              style: TextStyle(fontSize: 12, color: Color(0xFF607889)),
            ),
          ],
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
