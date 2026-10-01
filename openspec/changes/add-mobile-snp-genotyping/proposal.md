## Why

GeneEdge 需要在手機離線查詢 USB gene dongle 並判定 SNP 基因型，不依賴 Python 或網路。使用者指定直接讀取 USB 上的 combined 檔案、不讀手機內部資料；AI 仍維持 URL API。

為實機驗證結果與定位 USB 效能瓶頸，需要可開關的 debug mode，輸出計數與基因型結果，並區分 I/O、實際計算及整體耗時。

使用者需要像原本 App 一樣按主題選擇 SNP set，先以內建酒精 143 SNP 實測完整離線流程，不能要求使用者手動貼入序列。

## What Changes

USB偵測圖示追加需求：全部整合到原本聊天室上方下拉設定區，插入時在該區標頭顯示USB icon，滑鼠hover或手機長按顯示目前選定資料夾的可讀名稱；展開既有下拉設定可授權／選來源／調整debug。用標頭圖示取代訊息流中佔位的USB來源卡片，不新增獨立AppBar設定按鈕或bottom sheet，聊天畫面保留。尚未授權或多組未選時顯示待設定狀態，不冒充運算就緒；插入／hover／展開設定不啟動SNP，只有送出聊天訊息才計算。

2026-10-01介面修正（優先於下面已完成版本的獨立離線模式描述）：使用者要求類似原BLE／Auto的送出→運算→結果訊息流程，USB是資料來源、手機C是運算端，不切換聊天室畫面、不要求額外USB離線開關。插入後辨識USB與授權狀態，發送訊息時依目前主題set計算，文字／進度／結果與API JSON在原訊息流呈現。既有沒有USB時的聊天路徑保留；此修正仍停在產生API JSON，不新增自動LLM傳輸。

- 移除聊天室USB離線開關及替換整個聊天body的計算畫面，保留既有聊天泡泡、主題選擇與輸入框；USB狀態／授權／來源選擇與debug採簡潔可展開操作。
- USB掛載時送出訊息選擇手機C路徑，單一合法來源可沿用原生自動選定；多組／未授權／panel未就緒明示阻擋，不悄悄改用BLE／Local JSON／雲端。
- 在既有訊息流末端顯示本次暫存使用者訊息與計算回覆卡片，不寫入聊天歷史、不自動TTS；原77位點統計模型與API JSON不變。

追加需求：直接在原有聊天室，以USB離線模式及既有健康主題選擇SNP set，輸入問題後執行C運算並產生既有API可用JSON；同位點只輸出一個統計模型判定的基因型。以下獨立頁與二等位模型為已完成的基礎功能，聊天室新增聯合位點模式，不把舊143列結果直接合併。

- 新增同位點共同read去重的四鹼基計數與獨立C Dirichlet-multinomial Bayesian caller；比較10種二倍體genotype，取最大posterior，深度不足／低posterior／並列保持no-call。
- 聊天室內提供USB來源／授權、主題set載入、離線送出、進度／取消、結果卡片與既有debug分段計時，不自動呼叫AI API。
- 輸出既有`/v1/ask`欄位與每位點唯一`rsID-實際鹼基GT`；完整研究診斷另保留posterior、模型版本、no-call與set版本，不把診斷欄位混入API request。

- Flutter 新增獨立手機 SNP 運算頁，沿用 USB 授權並選定同資料夾的 IDX 與 IDs，直接唯讀存取；不複製大型資料到手機。
- 新增可由 Flutter 呼叫的 C 原生引擎，支援 13-mer 二進位索引、64 位元位置、稀疏 read 計數、背景運算與取消。
- 新增獨立 beta-binomial 模型，以去重後 REF／ALT 計數評估二倍體 0/0、0/1、1/1，輸出 posterior 與 no-call；不沿用 demo 的 genotyping。
- 顯示未校準模型警示、模型版本、有效深度、模糊 read 與 REF／ALT 支持數。
- 保留 USB 匯入與 AI API 原有責任；直接運算依賴 USB 掛載，但不依賴匯入完成。
- 新增預設關閉的 debug mode：顯示與複製結構化結果、每個 SNP 與整個工作的分段計時；啟用時 Android logcat 輸出結果摘要，不輸出原始序列、read ID 或來源 URI，不自動儲存或上傳。
- SNP 頁改以主題 set 選單為主要入口，內建並預選「酒精代謝（77 位點／143 查詢）」，自動載入原始參考 FASTA，以完整REF／ALT query id保留同位點不同ALT的獨立二等位查詢，不宣稱多等位聯合GT；其他尚未有資料的主題標示未提供並禁用，保留單 SNP／外部 FASTA 為進階功能。
- 驗證選酒精 set、載入143筆、直接讀USB、C計數、genotyping、結果／分段計時的完整流程到LLM之前，不自動呼叫或變更AI API。

## Capabilities

### New Capabilities

- `mobile-snp-genotyping`: 手機檔案選取、C 索引計數、獨立 beta-binomial 判定、Flutter 主題 set 操作、內建酒精資料及 debug 結果／分段計時。

### Modified Capabilities

無。

## Impact

- Affected specs: mobile-snp-genotyping
- Affected code:
  - New: `android/app/src/main/cpp/snp/snp_engine.c`, `android/app/src/main/cpp/snp/snp_engine.h`, `android/app/src/main/cpp/snp/genotype_model.c`, `android/app/src/main/cpp/snp/genotype_model.h`, `android/app/src/main/cpp/snp/snp_bridge.cpp`, `android/app/src/main/kotlin/com/example/geneapp/SnpComputePlugin.kt`, `android/app/src/main/kotlin/com/example/geneapp/snp/SnpContracts.kt`, `android/app/src/test/kotlin/com/example/geneapp/snp/SnpContractsTest.kt`, `lib/snp_compute.dart`, `lib/snp_compute_page.dart`, `test/snp_compute_test.dart`, `test/snp_compute_page_test.dart`, `test/snp_compute_navigation_test.dart`, `test/native/snp_engine_test.c`, `test/native/genotype_model_test.c`, `test/native/snp_pipeline_test.c`, `test/native/jni/com/example/geneapp/SnpComputePlugin.java`, `scripts/test_snp_native.sh`, `docs/mobile-snp-genotyping.md`
  - Modified: `android/app/src/main/cpp/CMakeLists.txt`, `android/app/src/main/kotlin/com/example/geneapp/MainActivity.kt`, `lib/chat_room_page.dart`
- Dependencies: 既有 Android NDK／CMake、JNI、Dart MethodChannel；不新增 GATK、Python 或網路服務。
- Set 追加影響：新增 `assets/snp_sets/alcohol.set143.k150.fasta`、`lib/snp_sets.dart`、`test/snp_sets_test.dart`，修改 `pubspec.yaml`、`lib/snp_compute.dart`、`lib/snp_compute_page.dart` 及既有 SNP tests／操作文件；不將 USB combined 或任何個人 read 打包入 App。
- 聊天室／聯合模型追加影響：新增C `locus_genotype_model.c/.h`、`test/native/locus_genotype_model_test.c`、`test/native/snp_locus_test.c`，Flutter `snp_api_payload.dart`、`snp_chat_panel.dart`及對應tests；修改既有SNP engine／bridge／plugin／contracts、CMake、`snp_sets.dart`、`snp_compute.dart`、`chat_room_page.dart`及驗證腳本。`api_service.dart`現有JSON契約只作相容性依據，不改URL或自動傳輸行為。
- 介面修正影響：`lib/chat_room_page.dart`、`lib/snp_chat_panel.dart`、必要的`lib/snp_compute.dart`來源狀態介面、`test/snp_chat_panel_test.dart`及`docs/mobile-snp-genotyping.md`。不更動C模型／原生IDX格式／BLE演算法或AI URL。
- USB icon追加影響同上述Flutter介面／tests／操作文件，沿用sources.label顯示選定資料夾，不新增原生路徑讀取或URI洩露。
