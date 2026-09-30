import 'package:flutter/material.dart';

import 'usb_gene_dongle.dart';

/// Data acquisition only: this page never invokes computation or the AI API.
class UsbGeneDonglePage extends StatefulWidget {
  final UsbGeneDongleController controller;

  const UsbGeneDonglePage({super.key, required this.controller});

  @override
  State<UsbGeneDonglePage> createState() => _UsbGeneDonglePageState();
}

class _UsbGeneDonglePageState extends State<UsbGeneDonglePage> {
  @override
  void initState() {
    super.initState();
    widget.controller.start();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('USB / Gene dongle')),
        body: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final snapshot = widget.controller.snapshot;
            final imported = snapshot.imported;
            final busy = widget.controller.busy ||
                snapshot.state == UsbGeneDongleState.scanning;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Icon(Icons.usb_rounded, size: 48),
                const SizedBox(height: 16),
                Text(
                  _stateText(snapshot.state),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  '插入 USB 後自動偵測已掛載的儲存裝置。首次使用請授權含資料的資料夾；'
                  '之後在授權有效時自動讀取。手機也可能列出可移除的 SD 卡。',
                ),
                const SizedBox(height: 8),
                const Text(
                  '資料夾中必須同時包含 combined_ids_all.txt 與 combined_idx_all.txt。'
                  '此功能只匯入原始資料，不會啟動離線計算或傳送至 AI API。',
                ),
                if (snapshot.errorCode != null) ...[
                  const SizedBox(height: 12),
                  Text(_errorText(snapshot.errorCode!),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                if (busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed:
                      busy || snapshot.state == UsbGeneDongleState.unsupported
                          ? null
                          : widget.controller.refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新掃描'),
                ),
                for (final volume in snapshot.volumes)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(volume.label,
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(volume.authorized ? '資料夾已授權' : '尚未授權資料夾'),
                          TextButton.icon(
                            onPressed: busy
                                ? null
                                : () =>
                                    widget.controller.requestAccess(volume.id),
                            icon: const Icon(Icons.folder_open),
                            label:
                                Text(volume.authorized ? '重新選擇資料夾' : '授權資料夾'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (imported != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    snapshot.state == UsbGeneDongleState.ready
                        ? '已保存的資料'
                        : '上次匯入的資料',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Text('雙檔已保存到 App 私有空間，拔除 USB 後仍保留。'),
                  const SizedBox(height: 12),
                  _FileMetadata(
                      name: UsbGeneDongleImport.idsFileName,
                      bytes: imported.idsBytes),
                  _FileMetadata(
                      name: UsbGeneDongleImport.idxFileName,
                      bytes: imported.idxBytes),
                  const SizedBox(height: 12),
                  Text('來源資料夾：${imported.folderName}'),
                  const Text('來源 URI'),
                  SelectableText(imported.sourceUri),
                ],
              ],
            );
          },
        ),
      );
}

String _stateText(UsbGeneDongleState state) => switch (state) {
      UsbGeneDongleState.unsupported => 'USB 匯入目前僅支援 Android',
      UsbGeneDongleState.noDevice => '未偵測到 USB 儲存裝置',
      UsbGeneDongleState.permissionRequired => '需要資料夾授權',
      UsbGeneDongleState.scanning => '正在搜尋並讀取資料',
      UsbGeneDongleState.ready => '資料已匯入',
      UsbGeneDongleState.missingFiles => '找不到完整的雙檔資料',
      UsbGeneDongleState.ambiguous => '找到多組資料，請縮小授權範圍',
      UsbGeneDongleState.error => '資料讀取未完成',
    };

String _errorText(String code) => switch (code) {
      'permission_denied' => '尚未授權，可再次選擇資料夾。',
      'invalid_source' => '請選擇目前已連接的 USB／可移除儲存裝置資料夾。',
      'empty_file' => '資料檔案是空的，請檢查 USB 裡的雙檔。',
      'file_too_large' => '檔案超過目前每檔 256 MiB 的匯入上限。',
      'scan_limit' => '資料夾範圍過大，請直接授權包含雙檔的資料夾。',
      'cancelled' => '讀取已中止，可重新掃描。',
      'io_failed' => '無法完整讀取資料，請確認 USB 連線後重試。',
      _ => 'USB 讀取服務暫時無法使用，請重新掃描或重新開啟 App。',
    };

class _FileMetadata extends StatelessWidget {
  final String name;
  final int bytes;

  const _FileMetadata({required this.name, required this.bytes});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.description_outlined),
        title: Text(name),
        subtitle: Text('$bytes bytes'),
      );
}
