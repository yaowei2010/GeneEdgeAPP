## Context

現有 USB 功能採 SAF 唯讀授權並匯入私有儲存，每檔上限 256 MiB。真實 IDX 為 512 MiB，IDs 約 28.1 GiB，手機運算不能依賴此匯入。原始 C 採約 10 GiB dense counters 並由 Python 以門檻判定基因型；本變更以獨立 C 引擎替換兩者。

## Goals / Non-Goals

Goals：直接讀 USB、Flutter 呼叫 C、去重 SNP 計數、獨立 beta-binomial 模型、可取消與可追溯結果。
Non-Goals：手機內部 combined 資料、複製完整 USB 資料、FASTQ 建表、GATK／PairHMM 等效、品質分數推造、臨床認證、改變 AI API。

追加範圍：debug mode 的結果顯示／複製、logcat 摘要與單調時鐘分段計時；不包含背景持續監控、原始 reads 輸出、自動保存／上傳或改變計數與模型判定。

追加範圍：以原本 App 主題語彙呈現 SNP set 選單、內建酒精143筆參考查詢，以及從 set 選取到離線結果的測試。不把聊天主題本身當成 SNP 資料，不捏造尚未提供的 set，也不新增自動 LLM 串接。

## Decisions

### USB 直接讀取

重用 USB 掛載識別、SAF 授權及同目錄雙檔發現，但另設計算資料來源，不能以匯入成功作為前提。有兩組雙檔時列出資料夾讓使用者選擇，禁止自動猜測。唯讀 openFileDescriptor 後以 seek/pread 探測隨機存取，不支援則明確失敗，不改用寫入授權或完整複製。native 複製描述符取得所有權，所有結束路徑關閉。

### 稀疏 C 計數

獨立 C99 函式庫以固定寬度型別讀取 little-endian 格式：IDX 每桶八 bytes，低 32 位 offset 加第二字高八位組成 40 位 posting index，第二字低 24 位為 count；IDs 為 uint32 read ID。檢查 offset/count 與檔案大小，使用 64 位元 pread。查詢限制 301 bp A/C/G/T、SNP 位置 150（0-based）、REF/ALT 不同且各一個鹼基，形成兩條僅中心不同的查詢序列並查正向／反向互補。沿用 K=13、step=2、READ_MAX=65536、背景 coverage 門檻大於 58；高頻桶跳過量須輸出，不偽造支持證據。以完整 read ID 作 key，每條 read、每個方向／查詢位置最多一次命中；合併方向後每個 read 只計一次 total。REF-only 或 ALT-only 歸類，雙方都有支持時較高者勝、平手為 ambiguous，無等位支持為 coverage-only。稀疏表最高 100 萬候選 read，超限報 RESOURCE_LIMIT，不截斷後宣稱成功。候選 SNP 逐筆執行，取消每個桶及每批讀取檢查。

### Beta-binomial 判定

模型與計數分離。r 為 REF、a 為 ALT，n=r+a，禁止拿 coverage-only 或 ambiguous 當深度。對 g=0,1,2 計算 log C(n,a)+log B(a+alpha_g,n-a+beta_g)-log B(alpha_g,beta_g)，加 log prior_g 後以 log-sum-exp 正規化；實作消去所有genotype共同項以減少數值抵銷。mu=(epsilon,0.5,1-epsilon)，concentration=1/rho-1，alpha=mu*concentration，beta=(1-mu)*concentration。研究預設版本 bb-research-v1：epsilon=0.01、rho=0.02、prior=(1/3,1/3,1/3)、minDepth=10、minPosterior=0.99；這些是可測試的假設而非已校準測序品質。有限值與範圍必須驗證：epsilon在[1e-6,0.5)、rho在[1e-6,1-1e-6]、prior各自正且總和1（容差1e-9）、depth最多100萬，非有效參數報錯。深度不足、最大 posterior 小於門檻或並列則 GT=./. 並提供原因。UI 固定顯示未校準、非 GATK 等效警示。

### Flutter 背景整合

SnpComputePlugin 擁有工作排程、描述符與 native job 生命週期，MethodChannel geneedge/snp_compute 提供 sources、selectSource、run、cancel，EventChannel geneedge/snp_compute/events 提供 jobId、revision、status、completed、total。C engine 擁有索引解析、計數及取消檢查；genotype_model 擁有機率與 no-call。Dart controller 僅管理狀態與過期事件抑制，不重寫演算法。刪除任一 native 模組會失去資料验证／統計行為，並非空轉 wrapper。頁面支援貼入單一 301 bp 序列及 REF/ALT、選取面板 FASTA：面板 header 最後兩欄 REF_ALT，序列中心須為 REF 或 ALT並正規化；最多3000 loci，重複標識或不合法序列整批拒絕。顯示每 locus 計數、posterior、GT/no-call、模型參數及來源資料夾，不記錄個人 reads。

### Debug 結果與分段計時

頁面提供預設關閉的 debug 開關，運算中不能切換，每次 run 固定捕捉 debugEnabled。不以整個 native 呼叫時間冒充純計算時間：USB 隨機讀取與 SNP 計數交錯，必須在 C 引擎的實際 fstat／pread 呼叫前後累計單調時間。JNI 量測 SNP 查詢總時間與獨立 genotype_call 時間；純計數時間為 SNP 查詢總時間扣除其 I/O。Android 另量測開啟兩個 USB FD、大小／seek 檢查及完整工作時間。這些為經過時間（wall-clock），不是 CPU 使用時間；USB I/O 包含 provider／系統快取，不宣稱等同實體磁碟讀取時間。未選用 CPU profiler，避免擴大需求。

所有時間以毫秒輸出有限非負值，以未四捨五入數值計算分解。結果列的可選 debugTiming 包含 ioMs、countMs、genotypeMs、nativeTotalMs、nativeOverheadMs；nativeTotalMs = ioMs + countMs + genotypeMs + nativeOverheadMs。完整工作 debugTiming 包含 setupIoMs、queryIoMs、countMs、genotypeMs、overheadMs、totalMs；前三個逐列階段 queryIoMs／countMs／genotypeMs 分別加總，totalMs = setupIoMs + queryIoMs + countMs + genotypeMs + overheadMs。totalMs 從 worker 開始執行到結果結構建置完成，包含開檔、驗證、各 SNP 執行與 native／Android 結果處理，不含等待排程、Flutter 渲染、複製或 logcat 輸出；overheadMs 收納 nativeOverheadMs 和橋接／控制／結果處理等其餘時間。失敗／取消只提供已量測的 elapsedMs 與狀態，不偽造完整成功分解；不把部分 SNP 列當完成結果。

run 的 debugEnabled 預設 false，舊呼叫仍可運作；關閉時省略 debugTiming、不建立 debug 報告、不寫基因結果 logcat。啟用時完成事件包含整批 debugTiming，每列包含 debugTiming；Dart 驗證有限值、非負值及分解一致性（絕對容差 0.01 ms），無效資料走既有 INVALID_FORMAT。新增 schemaVersion=1 的 debug 報告，包含 jobId、狀態、進度、階段時間，以及每列既有 id、計數、REF／ALT、GT、posterior、noCallReason、模型版本／参数；不包含查詢序列、原始 read ID、sourceId／來源 URI 或檔案內容。

Flutter 顯示可選取報告及「複製 debug 結果」按鈕，逐 SNP 顯示時間，完整工作顯示分段總時間。Android 以 GeneEdgeSnp tag 輸出每個 SNP 的精簡結果與階段時間，以及工作終止摘要，單行限制 3000 UTF-8 bytes；保留數值結果，過長 locus id 截短並以 JSON escaping 防止換行注入。開關旁提示 SNP 結果亦屬敏感資料，複製後進入剪貼簿、啟用後出現在 logcat；只有使用者點擊才複製，無網路呼叫或持久化。來源變更、取消與拔除沿用既有 stale guard，清除可複製報告。

### SNP set 選單與內建酒精資料

以 `lib/snp_sets.dart` 管理明確 set catalog，而不是直接把 `ChatTopic` 名稱當成可運算 panel。目錄沿用原本頁面的酒精代謝、藥物反應、記憶認知、心理狀態、高血壓、血脂管理、營養建議標籤；本次只有酒精可選，其餘顯示「尚未提供 SNP set」並禁用，未來提供實際資料才啟用。預設模式為主題 set、預選 alcohol-set143-k150-v1；每個 catalog entry 包含 id、label、assetPath、expectedCount、來源描述與版本。單 SNP 與外部 FASTA 移到進階模式，保留現有驗證及匯入能力，避免把原本手動表單當主要操作。

酒精來源是 `/Volumes/Untitled/MXIC_NCKU_demo_v4/ref_dataset/alcohol.set143.k150.fasta`，原始 SHA-256 為 `0bc77278d47ddcf41f1bbf4ef6f879d47f86c2d06791c0e29c5c0812a72b73f9`。實作時將原始 bytes 內建於 `assets/snp_sets/alcohol.set143.k150.fasta`，在 `pubspec.yaml` 宣告；不採用 gene_annotated 版本，不使用 remoteV3 的另一份資料。沿用 `SnpQuery.parseFasta` 解析最後兩欄 REF／ALT，保留 rsID／chromosome／position 組成的既有 locus id 與檔案順序，例如 `rs1229984_4_100239319`，不擅自反轉等位方向。完整解析後需恰143筆、不重複、全部301bp ACGT、中心為 REF 或 ALT且兩者不同；任一失敗整組不可開始並顯示載入錯誤，禁止改用單 SNP 或另一個 set 作 silent fallback。

asset 載入顯示 loading／ready／error 與 set 名稱、版本、筆數，只有 ready 且 USB來源已選才可執行。選單、進階模式及輸入在 busy 時禁用；載入請求帶 generation，晚到舊載入不可覆蓋新模式。切換 set／模式時清除舊結果與 debug 報告，job 固定捕捉 setId／setLabel／setVersion及143筆 queries，完成頁與 debug 報告標明此次實際運算 set，不能拿目前選單重新標記舊結果。手動模式標明單 SNP 或自訂 FASTA，不冒充內建酒精。

完整驗收路徑為：選酒精→asset驗證143筆→USB唯讀授權／pair選取→C SNP計數→獨立C genotyping→143列結果／no-call及debug階段时间。Widget／controller 測試用 fake platform 驗證傳入的143筆與實際asset相同、完成列數及set版本；native／JNI fixture 仍負責驗證核心計數及模型，不能用fake平台冒充實機USB。Pixel實測记录手機、set版本、USB來源、完成／錯誤、计時、取消與拔除；未知真實GT不當正確性證據，需用人工已知fixture或獨立核對。離線功能不送出 HTTP／LLM 呼叫；本次「整個流程」驗收界線是 LLM 之前，原本AI URL API不變。

## Implementation Contract

- Source：只接受目前掛載的 removable USB 且已授權 SAF tree 下的同目錄精確双檔，拒絕 primary 手機儲存與非授權 URI；IDX 大小必須為536870912，IDs 必須非空且四 bytes 對齊。資料來源變更、USB 移除、Activity detach 均取消工作並使現有結果失效。
- Engine：snp_engine 接收兩個唯讀可 seek 描述符、locus 與取消 callback，回傳 total/ref/alt/ambiguous/coverageOnly/skippedBuckets 或錯誤；total=ref+alt+ambiguous+coverageOnly。不修改來源。
- Model：genotype_model 接收有效 r/a/config，回傳三個 posterior、GT、effectiveDepth、noCallReason、modelVersion、calibrated=false。零深度不產生成功 GT，參數錯誤不 fallback。Android回傳每列另包含refAllele、altAllele、sourceId與sourceLabel，Flutter缺少這些provenance則拒絕結果。
- IPC：run 回傳 jobId；完成事件含結構化結果與相同 jobId。每次只允許一個 job；重複 run 報 BUSY。cancel 冪等，UI 不把已取消、舊 revision 或不同來源結果當成功。錯誤碼包括 PERMISSION_DENIED、USB_REMOVED、SOURCE_AMBIGUOUS、NOT_SEEKABLE、INVALID_FORMAT、INVALID_QUERY、INVALID_MODEL、RESOURCE_LIMIT、IO_ERROR、CANCELLED、UNSUPPORTED_PLATFORM；禁止模擬資料 fallback。
- Acceptance：native 稀疏 fixture 驗證跨4GiB offset、重複 IDs、雙方向去重、平手、讀取失敗、取消及上限；model 測試零／低深度、對稱性、posterior總和、極端計數與非法参数。Android 測試授權／來源驗證與生命週期；Flutter 測試開始、進度、取消、錯誤、研究警示與 stale event。分析、既有 USB 回歸、ARM64 APK build 與 Pixel 真實 USB 實測分别記錄。
- Scope：只開發上述手機端離線功能；不修改 USB 舊匯入算法、AI API、TTS 或模型權重。
- Debug：實作 Debug 結果與分段計時 契約；實際演算法仍在 C，計時不改變 GT 或 evidence partition。以可控制時鐘／合成階段數值測試 I/O 扣除與加總、native 真實 fixture 的時間非負及 debug on/off 結果相同；Flutter 測試預設關閉、run 快照、顯示／複製、非法時間與 stale 清除，Android 測試 log 開關、隱私欄位及取消摘要。實機時間只有 Pixel／USB 可用後記錄，不承諾未知速度。
- Sets：依 SNP set 選單與內建酒精資料 契約實作 catalog／asset／預設UI與set job快照；計數／判定仍呼叫既有C，不重寫為Dart。`test/snp_sets_test.dart` 驗證原始hash、143筆與指定rs1229984完整locus；controller／widget測試驗證載入、傳參、結果來源、切換清除及其他set禁用；整批失敗不宣稱完成143筆。

## Risks / Trade-offs

- k-mer 計數不同於 BAM read evidence → 校準與桌面 fixture 驗證；結果明示研究用途，不能稱 GATK 等效。
- USB provider 不支援 seek → 明確拒絕，保留唯讀權限。
- 去重、跳過高頻桶與原始 demo 不完全一致 → 文档列出演算法差異，以小型人工 fixture 為基準，不宣稱逐位相同。
- 原生稀疏記憶體／USB 延遲 → 上限、取消、逐 locus 工作與實測；無未量測效能承諾。
- 高頻讀取計時增加測量成本 → debug 關閉時跳過逐次計時，報告註明 debug 開啟的量測開銷；開關不改變計數／模型結果。
- debug 結果仍可能包含敏感基因資訊 → 預設關閉、顯式隱私提示、移除原始資料與 URI，不自動上傳／保存。
- 主題有名稱但尚無對應資料 → catalog 明示不可用；本次僅內建使用者指定酒精參考panel，不把AI主題誤當資料來源。

## Migration Plan

先備份現有版本到 Git，再新增獨立函式庫與頁面；現有功能不遷移。若需要回退，使用備份 commit 重建 APK，不清除 USB 或使用者資料。

debug 實作前，另將目前已完成的 SNP 版本建立限定本功能檔案的 Git 備份 commit 與遠端 codex/ 備份分支，驗證遠端 commit；不夾帶其他功能的變更。

此備份也必須在 SNP set UI／asset 程式修改前完成。新版建置後不自動標記3.3為完成；先記錄安裝成功，再獨立記錄實際USB流程驗收。

## Open Questions

無阻擋實作的設計選項。模型校準及 Pixel 真實 USB 效能屬驗收中需量測事項，不冒充已完成。
