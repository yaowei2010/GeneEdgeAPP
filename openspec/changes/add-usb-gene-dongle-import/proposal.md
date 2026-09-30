## Why

Gene dongle 在 USB 儲存裝置提供 combined_ids_all.txt 與 combined_idx_all.txt。目前 App 只在啟動時載入 Local JSON，沒有偵測 USB、記住授權或讀取原始雙檔的能力。先建立獨立匯入功能，才能後續接手機離線計算。

## What Changes

- Android 在 App 使用期間與回到前景時偵測已掛載的非主要可移除儲存空間；不寫死 USB 路徑。
- 透過系統資料夾選擇器取得並保存讀取授權；未授權顯示提示，授權有效的裝置自動搜尋。
- 在授權範圍搜尋同一資料夾的原始雙檔，完整讀取並以交易方式保存至 App no-backup storage。
- 新增獨立「USB / Gene dongle」頁面，呈現裝置、來源 URI、檔名、bytes、匯入狀態、重掃與授權操作。
- 不觸發離線計算或 AI API、不推測雙檔內容格式、不將 gene dongle 資料寫入聊天紀錄。

## Capabilities

### New Capabilities

- `usb-gene-dongle-import`: Android 可移除儲存空間偵測、持久授權、成對檔案搜尋與私有匯入。

### Modified Capabilities

（無）

## Impact

- New: `lib/usb_gene_dongle.dart`, `lib/usb_gene_dongle_page.dart`, `test/usb_gene_dongle_test.dart`, `test/usb_gene_dongle_page_test.dart`, `android/app/src/main/kotlin/com/example/geneapp/UsbGeneDonglePlugin.kt`, `android/app/src/main/kotlin/com/example/geneapp/usb/GeneDongleImporter.kt`, `android/app/src/test/kotlin/com/example/geneapp/usb/GeneDongleImporterTest.kt`, `docs/usb-gene-dongle.md`。
- Modified: `android/app/src/main/kotlin/com/example/geneapp/MainActivity.kt`, `lib/chat_room_page.dart`, `test/widget_test.dart`。
- 使用 Android StorageManager、DocumentsContract、ContentResolver 與既有 Flutter channels；不新增全檔案存取權限或外部套件。
