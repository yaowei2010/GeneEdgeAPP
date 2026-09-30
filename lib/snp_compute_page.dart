import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'snp_compute.dart';
import 'snp_sets.dart';

class SnpComputePage extends StatefulWidget {
  const SnpComputePage({super.key, this.controller, this.setLoader});
  final SnpComputeController? controller;
  final Future<List<SnpQuery>> Function(SnpSet)? setLoader;
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
  bool advanced = false;
  SnpSet selectedSet = SnpSets.alcohol;
  List<SnpQuery>? setQueries;
  String? setError;
  int loadGeneration = 0;
  String? validationError;
  @override
  void initState() {
    super.initState();
    controller = widget.controller ?? SnpComputeController();
    WidgetsBinding.instance.addObserver(this);
    unawaited(controller.start());
    if (controller.supported) unawaited(loadSet());
  }

  Future<void> loadSet() async {
    final generation = ++loadGeneration, set = selectedSet;
    setState(() {
      setQueries = null;
      setError = null;
    });
    try {
      final queries = await (widget.setLoader?.call(set) ?? set.load());
      if (!mounted || generation != loadGeneration || advanced) return;
      setState(() => setQueries = queries);
    } catch (e) {
      if (mounted && generation == loadGeneration && !advanced) {
        setState(() => setError = 'SNP set 載入失敗：$e');
      }
    }
  }

  void changeMode(bool value) {
    if (controller.busy) return;
    loadGeneration++;
    controller.clearResults();
    setState(() {
      advanced = value;
      validationError = null;
    });
    if (!advanced) unawaited(loadSet());
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
      final queries = !advanced
          ? (setQueries ?? (throw const FormatException('SNP set 尚未載入')))
          : panel
              ? SnpQuery.parseFasta(fasta.text)
              : [
                  SnpQuery.validated(
                      id: id.text,
                      sequence: sequence.text,
                      ref: ref.text,
                      alt: alt.text)
                ];
      setState(() => validationError = null);
      await controller.run(queries,
          input: !advanced
              ? selectedSet.identity
              : SnpInputIdentity(panel ? 'custom-fasta' : 'single',
                  panel ? '自訂 FASTA' : '單 SNP', 'custom'));
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
  Widget timing(Map<String, double> t, {bool batch = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            '總耗時：${t[batch ? 'totalMs' : 'nativeTotalMs']!.toStringAsFixed(3)} ms'),
        if (batch) Text('USB 開檔／檢查：${t['setupIoMs']!.toStringAsFixed(3)} ms'),
        Text(
            'I/O 讀取：${t[batch ? 'queryIoMs' : 'ioMs']!.toStringAsFixed(3)} ms'),
        Text('SNP 計算：${t['countMs']!.toStringAsFixed(3)} ms'),
        Text('Genotyping：${t['genotypeMs']!.toStringAsFixed(3)} ms'),
        Text(
            '其他處理：${t[batch ? 'overheadMs' : 'nativeOverheadMs']!.toStringAsFixed(3)} ms'),
      ]);
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
                if (!advanced) ...[
                  DropdownButtonFormField<String>(
                      key: const ValueKey('snp-set-selector'),
                      initialValue: selectedSet.id,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'SNP set', border: OutlineInputBorder()),
                      items: SnpSets.catalog
                          .map((s) => DropdownMenuItem(
                              value: s.id,
                              enabled: s.available,
                              child: Text(
                                  s.available
                                      ? '${s.label}（77 位點／143 查詢）'
                                      : '${s.label} · 尚未提供 SNP set',
                                  overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: controller.busy
                          ? null
                          : (value) {
                              final set = SnpSets.catalog
                                  .firstWhere((s) => s.id == value);
                              if (!set.available) return;
                              controller.clearResults();
                              setState(() => selectedSet = set);
                              unawaited(loadSet());
                            }),
                  const SizedBox(height: 8),
                  if (setQueries != null)
                    Text('已載入 ${setQueries!.length} 筆等位查詢（77 位點）')
                  else if (setError != null)
                    Text(setError!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))
                  else
                    const Text('正在載入 SNP set…'),
                  Text('版本：${selectedSet.version}'),
                  const Text('每筆為獨立二等位查詢，不是多等位聯合 GT；同位點不同 ALT 的結果不合併。'),
                ],
                SwitchListTile(
                    title: const Text('進階：自訂查詢'),
                    value: advanced,
                    onChanged: controller.busy ? null : changeMode),
                if (advanced)
                  SwitchListTile(
                      title: const Text('使用 FASTA 面板'),
                      value: panel,
                      onChanged: controller.busy
                          ? null
                          : (v) {
                              controller.clearResults();
                              setState(() => panel = v);
                            }),
                if (advanced && panel) ...[
                  TextButton.icon(
                      onPressed: controller.busy ? null : pickPanel,
                      icon: const Icon(Icons.file_open),
                      label: const Text('選取 FASTA 面板')),
                  const Text(
                      '標頭：>標識_REF_ALT，例如 >rs123_C_T。最多 3000 筆，每筆 301 bp。'),
                  field('貼入 FASTA', fasta, lines: 5)
                ] else if (advanced) ...[
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
                SwitchListTile(
                  title: const Text('Debug：結果與分段計時'),
                  subtitle:
                      const Text('預設關閉。基因結果屬敏感資料；啟用後會出現在 logcat，複製會寫入剪貼簿。'),
                  value: controller.debugEnabled,
                  onChanged:
                      controller.busy ? null : controller.setDebugEnabled,
                ),
                Row(children: [
                  Expanded(
                      child: FilledButton(
                          onPressed: controller.busy ||
                                  controller.selectedSourceId == null ||
                                  (!advanced && setQueries == null)
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
                if (controller.resultInput != null)
                  Text(
                      '本次結果：${controller.resultInput!.label} · ${controller.resultInput!.version}'),
                if (controller.status == 'completed')
                  Text('完成 ${controller.completed} / ${controller.total} 筆查詢'),
                if (controller.elapsedMs != null)
                  Text(
                      '中斷時已耗時：${controller.elapsedMs!.toStringAsFixed(3)} ms（非完整計算）'),
                if (controller.batchTiming != null)
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('整批計時（經過時間，非 CPU 使用時間）'),
                                timing(controller.batchTiming!, batch: true),
                                const Text(
                                    'I/O 包含 provider／系統快取；debug 計時有額外開銷。總時間不含排程等待、UI 渲染、複製與日誌。'),
                              ]))),
                if (controller.debugReport != null) ...[
                  TextButton.icon(
                      onPressed: () async {
                        final report = controller.debugReport;
                        if (report != null) {
                          await Clipboard.setData(ClipboardData(text: report));
                        }
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('複製 debug 結果')),
                  ExpansionTile(title: const Text('查看 debug 結果'), children: [
                    Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(controller.debugReport!)),
                  ]),
                ],
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
                                if (r.debugTiming != null)
                                  timing(r.debugTiming!),
                              ]))),
              ]);
            }),
      );
}
