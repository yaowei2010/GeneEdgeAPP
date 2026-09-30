# 手機 USB 離線 SNP 運算

此版計數與 beta-binomial genotyping 均使用 C；Flutter 只管理輸入／畫面，Kotlin／JNI 只管理 USB 權限、FD 與工作生命週期。AI URL API 未修改，尚未把研究結果自動送至 LLM。

## 操作

1. 插入 USB，在聊天頁側欄開啟「手機 SNP 運算」。這是獨立入口，不需先完成舊「USB / Gene dongle」匯入。
2. 首次授予 USB 資料夾唯讀權限。來源必須是掛載的 removable 儲存 UUID，拒絕手機 primary 儲存。選定含精確檔名 combined_idx_all.txt 與 combined_ids_all.txt 的同目錄雙檔；多組時自行選擇。
3. 輸入單一 301 bp A/C/G/T 序列、REF、ALT；位置150（0-based，第151個字元）須為其中之一。或開啟 FASTA 面板，選檔／貼入文字，每筆 header 為 >標識_REF_ALT，最多3000筆、文字2MiB。面板是查詢定義，不是個人原始 reads。
4. 按「開始 C 離線運算」，查看進度與各 locus 結果。取消、拔除、變更來源會使工作與舊結果失效。

新計算入口直接按索引唯讀 USB，不完整複製 combined 檔案。原本 USB 匯入入口仍保有256MiB每檔上限，不能匯入真實大型pair；請使用新計算入口。USB provider 若不支援 seek，回報 NOT_SEEKABLE，不增加寫入權限或改用全檔複製。

## C 計數

IDX 必須為536870912 bytes，IDs非空且四byte對齊。little-endian IDX每桶八byte，posting位置40bit、count24bit；IDs每筆uint32 read ID。C 使用64bit pread，檢查範圍並分批讀取。

K13、step2，同時比較中心 REF／ALT 及反向互補；背景位置不雙算，posting重複不雙算。每方向的匹配位置數大於58才支持分類。完整read ID（含R1/R2來源bit）在兩方向合併後只計一次，R1與R2不宣稱已合併成獨立fragment。REF／ALT支持較高者歸類，平手且非零為ambiguous；皆零為coverage-only。total=REF+ALT+ambiguous+coverageOnly。

posting桶大於65536則跳過並回報skippedBuckets，不補造支持數。候選read上限100萬，超限報 RESOURCE_LIMIT，禁止截斷後成功。稀疏表最多約48MiB，rehash時約72MiB，另有批次buffer與UI結果。這是設計上限，不是Pixel量測值。

與demo差異：修正獨立read去重／尾端漏計風險、不累加同一read的兩方向depth、不補造被跳過桶的coverage、不使用dense10GiB陣列；因此不宣稱輸出与原始demo逐位相同。以人工fixture驗證，不以demo的疑似錯誤作真值。

## 研究模型

版本bb-research-v1，calibrated=false。有效深度n=REF+ALT，不包含ambiguous／coverage-only。各基因型 ALT 比例均值為epsilon、0.5、1-epsilon；concentration=1/rho-1；alpha=mu*concentration，beta=(1-mu)*concentration。計算beta-binomial likelihood加prior，用log-sum-exp正規化posterior。

固定研究預設：epsilon=0.01、rho=0.02、prior=(1/3,1/3,1/3)、minDepth=10、minPosterior=0.99。這些是尚未校準的假設，不是原始Base Quality。C接口拒絕非法／非有限參數：epsilon須在[1e-6,0.5)，rho在[1e-6,1-1e-6]，prior各自正且總和1（容差1e-9），有效depth最多100萬。

GT輸出0/0、0/1、1/1；零深度、低深度、最高posterior低於門檻或並列則./.，保留原因與posterior。此版不是GATK HaplotypeCaller等效，也非臨床判讀。k-mer evidence與BAM計數不同，R1/R2可能相關；需要已知GT資料校準與外部驗證後才能解讀信心。

## 驗證與限制

重跑C與JNI驗證：bash scripts/test_snp_native.sh。此命令只產生暫存測試binary／人工fixture，不讀USB個人資料、不連網。Flutter：flutter test、flutter analyze。Android：在android目錄執行 ./gradlew :app:testDebugUnitTest --tests 'com.example.geneapp.snp.*' --tests 'com.example.geneapp.usb.*' -PbluemagpiePoc=false。APK：flutter build apk --debug --target-platform android-arm64。

- 原版Git備份：457fba7，遠端分支codex/backup-before-mobile-snp-20260930。
- Native tests：snp_engine_test.c涵蓋跨4GiB／40bit、去重、58/59邊界、取消、錯誤及上限；genotype_model_test.c涵蓋獨立機率參考與數值邊界；snp_pipeline_test.c人工42 reads fixture含20REF／20ALT／1ambiguous／1coverage-only，驗證模型depth40及0/1。
- Native以C99、warnings-as-errors及UndefinedBehaviorSanitizer驗證。Apple本機AddressSanitizer在main前初始化卡住，未取得ASan驗證通過。
- Flutter完整48測試通過，analyze無問題；新增Android SNP九項與既有USB十項測試通過。Android完整suite有既有BlueMagpie ModelManifestParserTest權重大小不一致，未改動該模組，不能稱完整suite全綠。
- JVM host harness呼叫真正JNI bridge、C計數與C模型，驗證跨4GiB人工fixture、JSON欄位、ZERO_DEPTH、0/1、取消100次、Java callback例外及caller FD仍有效。此harness不是Android實機測試；Mac JVM不能載入UBSan dylib，因此JNI測試使用一般warnings-as-errors建置，C測試另以UBSan驗證。
- ARM64 debug APK已建置；Pixel未連線，真實USB seek、取消／拔除、記憶體、耗時與結果對照仍待驗收。不得把設計fixture當真實患者運算驗證。
- 尚未新增LLM傳輸；結果只在本機頁面顯示。不能宣稱整條到LLM的實機流程完成。
