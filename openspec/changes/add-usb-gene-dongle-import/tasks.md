## 1. 獨立原生與 Flutter 模組

- [x] 1.1 [P] 完成「Android 偵測與安全匯入」、「Android detection and persisted read authorization」、「Same-directory complete pair discovery」與「Transactional bounded raw file import」：worker 搜尋 SAF 雙檔、交易式 no-backup 複製、持久 grant、mount/removal/picker/detach 生命週期；依 TDD 先建立 GeneDongleImporterTest 並驗證 nested/split/multiple/empty/oversize/IO/cancel/cleanup，以 Android JVM tests 與 Kotlin compile 驗證。
- [x] 1.2 [P] 完成「Flutter 契約與生命週期」與「Isolated observable import lifecycle」：可注入 typed controller、遞增 revision、startup/events/refresh/requestAccess/dispose 與 unsupported fallback；以 usb_gene_dongle_test.dart 驗證 stale reply、cancel/error、single subscription 與 disposal。

## 2. 獨立入口與狀態頁

- [x] 2.1 依「獨立匯入介面」與「Isolated observable import lifecycle」建立 USB / Gene dongle 頁面與 Android-only drawer entry，聊天期間持續監聽、前景 resume 重掃；不接計算或 AI API，顯示 source URI/雙檔 bytes/last-import、授權與重掃；先寫 widget tests 再接 UI，驗證 missing/ambiguous/ready/no-device 與 navigation。

## 3. 回歸與交付

- [ ] 3.1 保存安裝與 USB 插入/授權/巢狀/再插入/拔除/錯誤的真機 checklist，明確區分自動驗證與未執行實機項目；執行 flutter analyze、flutter test、Android JVM tests、flag-off ARM64 APK、spectra validate，保存結果於 docs/usb-gene-dongle.md，確認 Git backup 可還原。

驗收紀錄：2026-09-30 Flutter 33 tests、USB JVM 10 tests、analyze 與 ARM64 APK 通過，備份已推送；完整 Android suite 31 tests 中 1 個原有 ModelManifestParserTest（Q4 預期與備份中的 Q8 manifest 不符）失敗。該測試與 manifest 未變更，詳細比對與未執行的 USB 真機清單保存於 docs/usb-gene-dongle.md。驗收尚未全部通過，因此此任務不勾選、不封存。
