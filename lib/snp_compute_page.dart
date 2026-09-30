import 'dart:async';
import 'package:flutter/material.dart';
import 'snp_compute.dart';

class SnpComputePage extends StatefulWidget {
  const SnpComputePage({super.key, this.controller});
  final SnpComputeController? controller;
  @override
  State<SnpComputePage> createState() => _SnpComputePageState();
}

class _SnpComputePageState extends State<SnpComputePage>
    with WidgetsBindingObserver {
  late final SnpComputeController controller;
  final sequence = TextEditingController(),
      ref = TextEditingController(),
      alt = TextEditingController(),
      id = TextEditingController(text: 'SNP-1'),
      fasta = TextEditingController();
  bool panel = false;
  String? validationError;
  @override
  void initState() {
    super.initState();
    controller = widget.controller ?? SnpComputeController();
    WidgetsBinding.instance.addObserver(this);
    unawaited(controller.start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(controller.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) controller.dispose();
    for (final c in [sequence, ref, alt, id, fasta]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> run() async {
    try {
      final queries = panel
          ? SnpQuery.parseFasta(fasta.text)
          : [
              SnpQuery.validated(
                  id: id.text,
                  sequence: sequence.text,
                  ref: ref.text,
                  alt: alt.text)
            ];
      setState(() => validationError = null);
      await controller.run(queries);
    } catch (e) {
      if (mounted) {
        setState(() => validationError =
            e is FormatException ? e.message.toString() : '無法開始計算');
      }
    }
  }

  Future<void> pickPanel() async {
    try {
      final text = await controller.pickPanel();
      if (text != null && mounted) {
        SnpQuery.parseFasta(text);
        setState(() {
          fasta.text = text;
          panel = true;
          validationError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => validationError = '無法讀取面板：$e');
    }
  }

  Widget field(String label, TextEditingController c, {int lines = 1}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
              controller: c,
              minLines: lines,
              maxLines: lines,
              enabled: !controller.busy,
              decoration: InputDecoration(
                  labelText: label, border: const OutlineInputBorder())));
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('USB 離線 SNP 運算')),
        body: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              if (!controller.supported) {
                return const Center(child: Text('此功能僅支援 Android 手機'));
              }
              return ListView(padding: const EdgeInsets.all(16), children: [
                const Card(
                    child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                            '研究模型尚未校準，非 GATK 等效，非臨床判讀。\n直接唯讀 USB combined 檔案，不複製至手機；AI API 為獨立功能。'))),
                Row(children: [
                  const Expanded(child: Text('USB 資料來源')),
                  IconButton(
                      tooltip: '重新掃描 USB',
                      onPressed: controller.busy ? null : controller.refresh,
                      icon: const Icon(Icons.refresh))
                ]),
                for (final v in controller.volumes)
                  ListTile(
                      title: Text(v['label'] as String),
                      subtitle:
                          Text(v['authorized'] == true ? '已授權' : '需要 USB 唯讀授權'),
                      trailing: v['authorized'] == true
                          ? null
                          : TextButton(
                              onPressed: controller.busy
                                  ? null
                                  : () => controller
                                      .requestAccess(v['id'] as String),
                              child: const Text('授權'))),
                if (controller.sources.isEmpty)
                  const Text(
                      '尚未找到 USB 同資料夾的 combined_idx_all.txt 與 combined_ids_all.txt。請插入並授權 USB。'),
                if (controller.sources.isNotEmpty)
                  DropdownButtonFormField<String>(
                      key: ValueKey(controller.selectedSourceId),
                      initialValue: controller.selectedSourceId,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: '選擇 USB 資料夾'),
                      items: controller.sources
                          .map((s) => DropdownMenuItem(
                              value: s['id'] as String,
                              child: Text(s['label'] as String,
                                  overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: controller.busy
                          ? null
                          : (v) {
                              if (v != null) {
                                unawaited(controller.selectSource(v));
                              }
                            }),
                const SizedBox(height: 16),
                SwitchListTile(
                    title: const Text('使用 FASTA 面板'),
                    value: panel,
                    onChanged: controller.busy
                        ? null
                        : (v) => setState(() => panel = v)),
                if (panel) ...[
                  TextButton.icon(
                      onPressed: controller.busy ? null : pickPanel,
                      icon: const Icon(Icons.file_open),
                      label: const Text('選取 FASTA 面板')),
                  const Text(
                      '標頭：>標識_REF_ALT，例如 >rs123_C_T。最多 3000 筆，每筆 301 bp。'),
                  field('貼入 FASTA', fasta, lines: 5)
                ] else ...[
                  field('SNP 標識', id),
                  field('301 bp 序列（中心為 REF 或 ALT）', sequence, lines: 4),
                  Row(children: [
                    Expanded(child: field('REF', ref)),
                    const SizedBox(width: 12),
                    Expanded(child: field('ALT', alt))
                  ])
                ],
                if (validationError != null)
                  Text(validationError!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                if (controller.errorCode != null)
                  Text('計算／USB 錯誤：${controller.errorCode}',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                Row(children: [
                  Expanded(
                      child: FilledButton(
                          onPressed: controller.busy ||
                                  controller.selectedSourceId == null
                              ? null
                              : run,
                          child: const Text('開始 C 離線運算'))),
                  const SizedBox(width: 12),
                  OutlinedButton(
                      onPressed: controller.busy ? controller.cancel : null,
                      child: const Text('取消'))
                ]),
                if (controller.busy) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                      value: controller.total == 0
                          ? null
                          : controller.completed / controller.total),
                  Text('進度 ${controller.completed} / ${controller.total}')
                ],
                Text('狀態：${controller.status}'),
                for (final r in controller.results)
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${r.id} · GT ${r.gt} ${r.noCallReason == null ? '' : '（no-call：${r.noCallReason}）'}'),
                                Text(
                                    '有效深度 ${r.effectiveDepth} · REF ${r.refAllele}: ${r.ref} / ALT ${r.altAllele}: ${r.alt}'),
                                Text('來源：${r.sourceLabel}'),
                                Text(
                                    '總 read ${r.total} · 模糊 ${r.ambiguous} · 僅覆蓋 ${r.coverageOnly} · 跳過桶 ${r.skippedBuckets}'),
                                Text(
                                    'Posterior 0/0=${r.posterior[0].toStringAsPrecision(5)} / 0/1=${r.posterior[1].toStringAsPrecision(5)} / 1/1=${r.posterior[2].toStringAsPrecision(5)}'),
                                Text('${r.modelVersion} · 未校準'),
                                Text('參數：${r.parameters}'),
                              ]))),
              ]);
            }),
      );
}
