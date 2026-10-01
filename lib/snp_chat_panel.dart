import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'snp_compute.dart';
import 'snp_api_payload.dart';
import 'snp_sets.dart';

/// Read-only header state; never substitutes a folder when none is selected.
class SnpChatUsbStatus {
  const SnpChatUsbStatus(
      {required this.controller,
      required this.set,
      required this.queries,
      required this.error});
  final SnpComputeController controller;
  final SnpSet set;
  final List<SnpQuery>? queries;
  final String? error;
  String? get selectedLabel {
    if (controller.selectedSourceId == null) return null;
    for (final source in controller.sources) {
      if (source['id'] == controller.selectedSourceId) {
        return source['label'] as String;
      }
    }
    return null;
  }

  bool get ready =>
      selectedLabel != null &&
      set.available &&
      queries != null &&
      controller.sourceConfirmed &&
      error == null;
  String get folderHint => selectedLabel == null
      ? 'USB 已偵測，請授權或選取資料夾\n$status'
      : 'USB・手機 C\n資料夾：$selectedLabel\n$status';
  String get status => !set.available
      ? 'USB 待設定：尚未提供 SNP set'
      : error ??
          (queries == null
              ? 'USB 待設定：正在載入 SNP set…'
              : selectedLabel == null
                  ? 'USB 待設定：請授權或選取資料夾'
                  : !controller.sourceConfirmed
                      ? 'USB 待確認：點擊 USB 圖示'
                      : controller.busy
                          ? 'USB 計算中'
                          : 'USB 已就緒');
}

class SnpUsbConfirmationDialog extends StatefulWidget {
  const SnpUsbConfirmationDialog(
      {super.key, required this.controller, required this.stillActive});
  final SnpComputeController controller;
  final bool Function() stillActive;
  @override
  State<SnpUsbConfirmationDialog> createState() =>
      _SnpUsbConfirmationDialogState();
}

class _SnpUsbConfirmationDialogState extends State<SnpUsbConfirmationDialog> {
  String? _volumeId;
  bool _changing = false;
  List<Map<Object?, Object?>> get _volumes =>
      widget.controller.volumes.isNotEmpty
          ? widget.controller.volumes
          : widget.controller.mountedUsbIds
              .map((id) => <Object?, Object?>{
                    'id': id,
                    'label': 'USB',
                    'authorized': true
                  })
              .toList();
  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    final selected = c.sources.where((s) => s['id'] == c.selectedSourceId);
    if (selected.isNotEmpty) {
      _volumeId = (selected.first['volumeId'] ??
          (c.volumes.isEmpty ? selected.first['id'] : null)) as String?;
    }
    if (_volumeId == null && _volumes.length == 1) {
      _volumeId = _volumes.single['id'] as String;
    }
  }

  Future<void> _change(Future<void> Function() action) async {
    if (_changing || widget.controller.busy || widget.controller.accessBusy) {
      return;
    }
    setState(() => _changing = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final c = widget.controller, volumes = _volumes;
        final chosen = volumes.where((v) => v['id'] == _volumeId);
        final volume = chosen.isEmpty ? null : chosen.single;
        final sources = c.sources
            .where((s) =>
                volume != null &&
                (s['volumeId'] == _volumeId ||
                    (s['volumeId'] == null && volumes.length == 1)))
            .toList();
        final selected = sources.any((s) => s['id'] == c.selectedSourceId)
            ? c.selectedSourceId
            : null;
        final locked = _changing || c.busy || c.accessBusy;
        final scopes =
            (volume?['authorizationScopes'] as List?)?.cast<String>() ??
                const <String>[];
        return AlertDialog(
          title: Row(children: [
            const Expanded(child: Text('USB 使用確認')),
            IconButton(
                tooltip: '關閉 USB 確認',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop())
          ]),
          content: SizedBox(
              width: 380,
              child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .45),
                  child: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        const Text('預設位置：USB 根目錄'),
                        const Text('首次仍需在系統頁面確認唯讀授權；若根目錄受限制，可授權含資料的子資料夾。'),
                        if (volumes.length > 1)
                          DropdownButtonFormField<String>(
                              key: const ValueKey('usb-confirm-volume'),
                              initialValue: volume?['id'] as String?,
                              isExpanded: true,
                              decoration:
                                  const InputDecoration(labelText: 'USB 裝置'),
                              items: volumes
                                  .map((v) => DropdownMenuItem(
                                      value: v['id'] as String,
                                      child: Text(v['label'] as String,
                                          overflow: TextOverflow.ellipsis)))
                                  .toList(),
                              onChanged: locked
                                  ? null
                                  : (id) => setState(() => _volumeId = id))
                        else if (volume != null)
                          Text(volume['label'] as String),
                        if (volume != null) ...[
                          Text(volume['authorized'] == true
                              ? '沿用唯讀授權：${scopes.isEmpty ? '已授權資料夾' : scopes.join('、')}'
                              : '尚未授權 USB 資料夾'),
                          if (c.volumes.isNotEmpty)
                            TextButton.icon(
                                onPressed: locked
                                    ? null
                                    : () => _change(
                                        () => c.requestAccess(_volumeId!)),
                                icon: const Icon(Icons.folder_open),
                                label: const Text('授權 USB 根目錄')),
                          if (sources.isEmpty)
                            const Text(
                                '授權後會搜尋同資料夾的 combined_ids_all.txt 與 combined_idx_all.txt；尚未找到可用來源。'),
                          if (sources.isNotEmpty)
                            DropdownButtonFormField<String>(
                                key: ValueKey(
                                    'confirm-source-$_volumeId-$selected'),
                                initialValue: selected,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'gene dongle 資料夾'),
                                items: sources
                                    .map((s) => DropdownMenuItem(
                                        value: s['id'] as String,
                                        child: Text(s['label'] as String,
                                            overflow: TextOverflow.ellipsis)))
                                    .toList(),
                                onChanged: locked
                                    ? null
                                    : (id) {
                                        if (id != null) {
                                          unawaited(_change(
                                              () => c.selectSource(id)));
                                        }
                                      }),
                        ],
                        if (locked)
                          const Padding(
                              padding: EdgeInsets.all(8),
                              child: LinearProgressIndicator()),
                        if (c.errorCode != null) Text('USB 狀態：${c.errorCode}'),
                        const Text('確認或關閉都不會計算；確認後送出聊天訊息才開始 SNP 計算。'),
                      ])))),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消')),
            FilledButton(
                onPressed: locked || selected == null
                    ? null
                    : () async {
                        final used = await c.confirmUsbSource(
                            stillActive: widget.stillActive);
                        if (used && context.mounted && widget.stillActive()) {
                          Navigator.of(context).pop();
                        }
                      },
                child: const Text('使用此 USB')),
          ],
        );
      });
}

class SnpChatJobCard extends StatelessWidget {
  const SnpChatJobCard({super.key, required this.controller});
  final SnpComputeController controller;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('USB・手機 C 計算回覆'),
            if (controller.busy) ...[
              Text('C 運算中：${controller.completed}／${controller.total} 位點'),
              LinearProgressIndicator(
                  value: controller.total == 0
                      ? 0
                      : controller.completed / controller.total),
              TextButton.icon(
                  onPressed: controller.cancel,
                  icon: const Icon(Icons.stop),
                  label: const Text('取消離線計算')),
            ] else
              Text(
                  '計算未完成：${controller.errorCode ?? controller.status}；未送至 API。'),
            if (controller.elapsedMs != null)
              Text('中斷前耗時：${controller.elapsedMs!.toStringAsFixed(3)} ms'),
          ])));
}

class SnpChatControls extends StatelessWidget {
  const SnpChatControls(
      {super.key,
      required this.controller,
      required this.set,
      required this.queries,
      required this.error});
  final SnpComputeController controller;
  final SnpSet set;
  final List<SnpQuery>? queries;
  final String? error;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${set.label} · USB 離線計算',
                style: Theme.of(context).textTheme.titleMedium),
            if (!set.available)
              const Text('尚未提供 SNP set，請切換健康主題；不會套用酒精資料。')
            else if (error != null)
              Text(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error))
            else if (queries == null)
              const Text('正在載入 SNP set…')
            else
              Text(
                  '已載入 ${queries!.length} 筆參考／${SnpLocus.group(queries!).length} 位點\n${set.version}'),
            const Text(
                '在下方輸入問題並送出，會用 C 計算及產生 JSON，不呼叫 AI API。\n研究模型尚未校準，非 GATK 等效、非臨床判讀。'),
            ExpansionTile(
                title: Text(controller.selectedSourceId == null
                    ? 'USB 來源與唯讀授權'
                    : 'USB 來源已選定'),
                initiallyExpanded: controller.selectedSourceId == null,
                children: [
                  TextButton.icon(
                      onPressed: controller.busy ? null : controller.refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新掃描 USB')),
                  for (final volume in controller.volumes)
                    ListTile(
                        title: Text(volume['label'] as String),
                        subtitle: Text(
                            volume['authorized'] == true ? '已授權' : '需要唯讀授權'),
                        trailing: volume['authorized'] == true
                            ? null
                            : TextButton(
                                onPressed: controller.busy
                                    ? null
                                    : () => controller
                                        .requestAccess(volume['id'] as String),
                                child: const Text('授權'))),
                  if (controller.sources.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                            '請插入並授權 USB；需在同資料夾找到 combined_idx_all.txt 和 combined_ids_all.txt。')),
                  if (controller.sources.isNotEmpty)
                    DropdownButtonFormField<String>(
                        key: ValueKey(controller.selectedSourceId),
                        initialValue: controller.selectedSourceId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'USB 資料夾'),
                        items: controller.sources
                            .map((s) => DropdownMenuItem(
                                value: s['id'] as String,
                                child: Text(s['label'] as String,
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: controller.busy
                            ? null
                            : (id) {
                                if (id != null) {
                                  unawaited(controller.selectSource(id));
                                }
                              }),
                ]),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Debug：結果與分段計時'),
                value: controller.debugEnabled,
                onChanged: controller.busy ? null : controller.setDebugEnabled),
            const Text('結果含敏感基因資訊；複製會寫入剪貼簿，Debug 也會輸出摘要至 logcat。',
                style: TextStyle(fontSize: 12)),
            if (controller.errorCode != null)
              Text('離線狀態：${controller.status}（${controller.errorCode}）'),
            if (controller.elapsedMs != null)
              Text('中斷前耗時：${controller.elapsedMs!.toStringAsFixed(3)} ms'),
          ])));
}

Widget _timing(Map<String, double> t, {bool batch = false}) => Text([
      '總耗時：${t[batch ? 'totalMs' : 'nativeTotalMs']!.toStringAsFixed(3)} ms',
      if (batch) 'USB 開檔／檢查：${t['setupIoMs']!.toStringAsFixed(3)} ms',
      'I/O 讀取：${t[batch ? 'queryIoMs' : 'ioMs']!.toStringAsFixed(3)} ms',
      'SNP 計算：${t['countMs']!.toStringAsFixed(3)} ms',
      'Genotyping：${t['genotypeMs']!.toStringAsFixed(3)} ms',
      '其他處理：${t[batch ? 'overheadMs' : 'nativeOverheadMs']!.toStringAsFixed(3)} ms',
    ].join('\n'));

class SnpChatResultCard extends StatelessWidget {
  const SnpChatResultCard({super.key, required this.controller});
  final SnpComputeController controller;
  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已複製；內容含敏感基因資訊')));
    }
  }

  @override
  Widget build(BuildContext context) {
    SnpApiPayload? export;
    try {
      export = SnpApiPayload.fromCompleted(controller);
    } on FormatException {
      return const Card(
          child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('API JSON 產生失敗：位點身份或結果不一致。')));
    }
    if (export == null) return const SizedBox.shrink();
    final payload = export;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('USB・手機 C 計算結果',
                  style: Theme.of(context).textTheme.titleMedium),
              Text('完成 ${controller.completed}／${controller.total} 位點'),
              Text(
                  '${controller.resultInput!.label} · ${controller.resultInput!.version}'),
              Text(
                  '可用 genotype：${payload.request['variant_used_count']} · no-call：${payload.request['no_call_count']}'),
              const Text('最佳 genotype 是模型估計，參數尚未校準。JSON 尚未送至 API。'),
              if (controller.batchTiming != null) ...[
                _timing(controller.batchTiming!, batch: true),
                const Text(
                    '計時為經過時間，非 CPU 時間；I/O 包含 provider／cache，Debug 有量測開銷。',
                    style: TextStyle(fontSize: 12)),
              ],
              FilledButton.icon(
                  onPressed: () => _copy(context, payload.apiJson),
                  icon: const Icon(Icons.copy),
                  label: const Text('複製 API JSON')),
              ExpansionTile(
                  title: const Text('查看 API JSON'),
                  children: [SelectableText(payload.apiJson)]),
              ExpansionTile(
                  title: const Text('每位點 genotype／posterior'),
                  children: [
                    for (final r in controller.locusResults)
                      ExpansionTile(
                          title: Text(
                              '${r.rsId} · ${r.actualGenotype ?? 'no-call'}'),
                          subtitle: Text(
                              'posterior：${(r.data['bestPosterior'] as double).toStringAsFixed(6)} · depth：${r.data['effectiveDepth']}'),
                          children: [
                            SelectableText(
                                'GT：${r.gt}\n${r.data['noCallReason'] ?? ''}\nAlleles：${r.data['alleles']}\nCounts：${r.data['baseCounts']}\nPosterior：${r.data['posterior']}'),
                            if (r.debugTiming != null) _timing(r.debugTiming!),
                          ]),
                  ]),
              if (controller.debugReport != null) ...[
                TextButton(
                    onPressed: () => _copy(context, payload.diagnosticJson),
                    child: const Text('複製 debug 結果')),
                ExpansionTile(
                    title: const Text('查看 debug 結果'),
                    children: [SelectableText(payload.diagnosticJson)]),
              ],
            ])));
  }
}
