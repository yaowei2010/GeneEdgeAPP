## Context

Android 最低 API 28。既有 LocalPayloadLoader 讀取 App 外部目錄的 JSON，不適用於 SAF content URI。使用者已要求更新前備份，備份分支 codex/backup-before-usb-20260930 已推送，commit 3f14508。雙檔的內容與計算規則尚未提供，本 change 只做原始資料匯入。

## Goals / Non-Goals

Goals：自動偵測可移除儲存空間、持久讀取授權、遞迴搜尋雙檔、完整匯入、独立狀態頁與可測試契約。

Non-Goals：手機計算、AI 模型、變更 URL API、背景啟動 App、任意新 USB 免授權、內容解析、把原始基因資料送至網路、iOS 支援。

## Decisions

### Android 偵測與安全匯入

獨立 UsbGeneDonglePlugin 使用 StorageManager 列出 mounted / mounted_ro 的非主要、可移除、具有 UUID 的 volumes；裝置名稱不能可靠區分 USB 與 SD，因此 UI 不宣稱每個 removable volume 都一定是 USB。使用 SAF ACTION_OPEN_DOCUMENT_TREE，僅接受 externalstorage.documents、其 document ID volume prefix 對應目前掛載 removable volume 的 tree URI。只持久化讀取權限，拒絕 primary/cloud/internal 選擇；不請求 MANAGE_EXTERNAL_STORAGE。

GeneDongleImporter 封裝成對搜尋、資源上限、完整串流讀取與交易式複製；Android URI adapter 實作列目錄與開啟串流，非 pass-through，隔離 provider/lifecycle 與配對規則。限制搜尋最多 10000 entries、16 層子目錄，每檔 256 MiB。任何超限都明確失敗，不默默截斷。相同資料夾的兩個固定名稱才成一組，多組回 ambiguous。目錄與檔案名稱只用於比對，不用來組裝私有輸出路徑。

先寫 App no-backup storage 新的私有暫存資料夾，雙檔完整、非空且取消檢查通過後才發布新 dataset；失敗清除本次 partial，保留上一份成功資料。串流按實際 bytes 限制，不信任 provider size。保留原始 bytes，不推論 UTF-8、行數或 IDs/IDX 格式。

### Flutter 契約與生命週期

Channel geneedge/usb_gene_dongle，events geneedge/usb_gene_dongle/events。Dart UsbGeneDongleController 以 ChangeNotifier 封裝 typed snapshot、listen/start/refresh/requestAccess 與 dispose，注入 UsbGeneDonglePlatform 支援 fakes。每個 native snapshot 帶遞增 revision，Dart 拒绝較舊 method reply 覆蓋新 event。

命令 refresh() / requestAccess({volumeId}) 回傳 snapshot；event 為同樣 schema。snapshot: revision:int, state:string, volumes:list[{id,label,authorized}], imported:nullable {datasetId,sourceUri,folderName,idsBytes,idxBytes}, errorCode:nullable string。states: unsupported, no_device, permission_required, scanning, ready, missing_files, ambiguous, error。error codes: permission_denied, invalid_source, io_failed, empty_file, file_too_large, scan_limit, cancelled。requestAccess 同時間只允許一個 picker。取消 picker 保留原 grant 並回 permission_denied。native 錯誤不帶 exception 或原始檔內容。

onListen 與 Flutter resume 掃描，mounted/unmounted/eject/removed/bad-removal 事件使舊掃描失效並重新掃描；worker 串列化昂貴 IO，main thread 回 channel result。detached engine/activity 結束 listener/picker、取消 worker，禁止晚到事件。重新掛載授權有效 volume 後自動重新讀取。若有新未授權裝置且找不到已授權完整資料組，回 permission_required。單次 scan 多組不自動選擇。

### 獨立匯入介面

聊天選單提供 Android-only USB / Gene dongle 入口。ChatRoomPage 擁有獨立 controller，聊天使用期間保持監聽；頁面回前景時 refresh。狀態頁顯示匯入狀態、volume label、來源 URI 與雙檔 byte size，提供個別 volume 授權按鈕與重新掃描。取得不到授權時清楚提示，不啟動計算或 API。已成功保存的 dataset 留在 App 私有空間，即使拔除也保留「上次匯入」資訊；目前狀態另顯示未連接。

## Implementation Contract

Behavior/interface/failure：以上三個 Decisions 為完整契約；mounted 初始與再插入偵測、grant validation、revision、精確檔名、同目錄配對、ambiguous、nonempty/bounds、雙檔交易、拔除/取消/晚到結果與不同於聊天的狀態必須測試。

Acceptance：GeneDongleImporterTest 用假 tree/stream 覆蓋巢狀搜尋、缺檔/跨目錄/多組、空檔、實際 bytes 超限、IO/取消時保留原資料與清除 partial。Dart tests 覆蓋 startup/events/refresh/dispose、unsupported、stale revision 與 picker cancellation。widget tests 覆蓋授權、ready metadata、missing/ambiguous、重掃與 Android drawer navigation。flutter analyze、flutter test、Android JVM tests 與 flag-off ARM64 debug APK 通過。實體 USB 的 SAF 授權與拔插另列 manual checklist，未執行不得宣告真機通過。

Scope：只匯入 raw pair 與保存本機 snapshot metadata；不接 ChatController.localMockPayload、不將 txt 轉 JSON、不呼叫 ApiService。

## Risks / Trade-offs

- 儲存裝置需手機 OS 掛載與支援檔案系統 → 顯示未偵測，保留重掃。
- 已授權子目錄之外不可搜尋 → 明示搜尋授權範圍，提供重新授權。
- USB/SD 都屬可移除 storage → 使用中性 volume label，不承諾硬體種類判定。
- 真實檔案大小未知 → 先固定 per-file 256 MiB 上限且明確回 file_too_large；不解讀資料。
- App 未執行時不主動啟動 → 下一次開啟或回前景列舉掛載裝置。
