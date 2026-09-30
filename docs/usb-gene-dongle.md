# USB / Gene dongle 匯入

Android App 進入聊天頁時、回到前景時，以及收到可移除儲存裝置的掛載／拔除事件時，自動列舉目前已掛載的儲存空間。使用者不需要輸入或猜測 /storage 路徑。

## 使用方式

1. 在手機插入 USB 隨身碟／gene dongle，確認 Android 系統檔案管理員能看到它。
2. 進入 GeneEdge 聊天頁，開啟左側選單 → **USB / Gene dongle**。
3. 首次使用按裝置的 **授權資料夾**，在系統選擇器選 USB 的資料資料夾並確認。只取得讀取權限。
4. App 自動搜尋授權目錄及子目錄。以下兩個名稱必須完全一致，且位於同一資料夾：
   - combined_ids_all.txt
   - combined_idx_all.txt
5. 顯示「資料已匯入」、來源 URI 與兩個檔案的 bytes，表示完整雙檔已保存至 App 私有 no-backup storage。
6. 同一 USB 再次插入，授權有效時自動搜尋並讀取。更換 USB 或授權失效需再次選擇資料夾。

來源為 Android SAF content URI，而非可交給 Dart File 的一般路徑。只搜尋已授權範圍；新 USB 不會自動跳過系統授權。Android 使用相同 StorageVolume API 表示 USB 與 SD 卡，因此頁面也能列出可移除 SD storage；不以裝置名稱推斷硬體種類。

## 匯入與計算分離

這次只實作原始双檔讀取與保存。不解析 IDs/IDX 格式、不轉為 Local JSON、不呼叫 ApiService，不啟動手機計算。既有 BLE／Local JSON／URL API 流程保留。後續離線計算可透過 datasetId 定位 Android noBackupFilesDir/gene-dongle/<datasetId>/ 下的固定雙檔；資料夾路徑不接受使用者輸入。

原始 bytes 保留，未要求文字編碼或行數。每檔上限 256 MiB；搜尋上限 10000 entries、16 層子目錄。找到多組資料時不任選一組，請重新授權到單一資料組的資料夾。缺檔、空檔、超限與無法讀取分別提示；失敗清除本次暫存，保留上一份成功資料。拔除 USB 顯示未連接，但「上次匯入的資料」仍保存；App 解除安裝會移除這些私有資料。

## 建置與驗證（2026-09-30）

- 更新前 GitHub 備份：分支 codex/backup-before-usb-20260930，commit 3f14508a5ee17a1b8fd5bba084e442b50673f7d2；Git ls-remote 已確認遠端分支指向該 commit。備份包含原本未提交的 BlueMagpie Q8/Vulkan 修改，不含忽略的模型權重。
- 開發分支：codex/usb-gene-dongle-import。
- flutter analyze --no-pub：無問題。
- flutter test --no-pub --reporter expanded：33 tests 全通過（既有 19 + USB controller 9 + USB UI 5）。
- Dart format 檢查與 git diff --check：通過。
- Android USB JVM suite：10 tests 全通過；compileDebugKotlin 通過。
- Android 全部 JVM tests：31 tests，30 通過，1 個既有 BlueMagpie ModelManifestParserTest 失敗。測試仍預期 Q4 byte size 693008576 與 Q4 SHA，但備份與目前 manifest 均為 Q8 byte size 1162038464。git diff 備份分支針對該測試與 manifest 為空，確認兩檔在 USB 開發中未變更。未修改或停用此既有測試。
- flutter build apk --debug --target-platform android-arm64 --no-pub：成功；產物 build/app/outputs/flutter-apk/app-debug.apk。BlueMagpie flag 關閉。
- spectra validate add-usb-gene-dongle-import：通過。

Android JVM 命令（android/ 目錄）：

```sh
JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' \
./gradlew :app:testDebugUnitTest -PbluemagpiePoc=false
```

## 實體手機驗收清單（尚未執行）

本次 adb devices 沒有已連接裝置；以下項目不能以 JVM/fake channel tests 代替。

- [ ] 插入已由 OS 掛載的 USB 後開啟 App：看到裝置與首次授權提示。
- [ ] App 在聊天頁期間插入 USB：不用重開 App 即能看到裝置。
- [ ] 授權 USB 含雙檔資料夾：顯示 ready、正確 URI 與實際 bytes。
- [ ] 完整雙檔位於授權目錄的子目錄：能自動找到。
- [ ] 系統 picker 取消或選手機內部儲存：提示錯誤且不匯入。
- [ ] 再次插入相同 USB／重開 App：不再要求授權且自動匯入。
- [ ] 拔除 USB：顯示 no_device，先前匯入資訊與私有資料仍在。
- [ ] 匯入中拔除 USB：不發布 partial，保留上一份完整資料，重新插入可復原。
- [ ] 缺少任一檔案／雙檔分在不同資料夾：顯示 missing_files。
- [ ] 授權範圍含兩組完整資料：顯示 ambiguous，縮小授權範圍後可匯入。
- [ ] 確認 USB 匯入不產生 API request，不把原始檔內容加入聊天或 log。

檔案內容格式與計算規則另立 change；本 change 在全套回歸失敗與真機驗收記錄補齊前保留於 openspec/changes/，不宣告已發布。
