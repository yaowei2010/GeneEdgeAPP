# 手機 USB 離線 SNP 運算

此版計數與 beta-binomial genotyping 均使用 C；Flutter 只管理輸入／畫面，Kotlin／JNI 只管理 USB 權限、FD 與工作生命週期。AI URL API 未修改，尚未把研究結果自動送至 LLM。

## 操作

1. 插入 USB，在聊天頁側欄開啟「手機 SNP 運算」。這是獨立入口，不需先完成舊「USB / Gene dongle」匯入。
2. 首次授予 USB 資料夾唯讀權限。來源必須是掛載的 removable 儲存 UUID，拒絕手機 primary 儲存。選定含精確檔名 combined_idx_all.txt 與 combined_ids_all.txt 的同目錄雙檔；多組時自行選擇。
3. SNP set 預選「酒精代謝（77 位點／143 查詢）」，自動載入內建參考資料，不需貼序列。確認「已載入143筆等位查詢」及版本alcohol-set143-k150-v1；其他主題尚未提供資料，不能執行。單SNP／自訂FASTA保留在「進階：自訂查詢」，沿用301bp／中心REF或ALT、最多3000筆及2MiB限制。
4. 若要檢查結果與耗時，先啟用「Debug：結果與分段計時」（預設關閉）。再按「開始 C 離線運算」，進度應到143/143，每列保留完整查詢ID、REF／ALT計數、posterior與GT／no-call。工作中不能切換模式／set／debug。
5. 完成後查看整批與逐筆計時，展開「查看 debug 結果」可選取JSON，或按「複製 debug 結果」。取消、拔除、變更來源或模式會清除結果與可複製報告；取消／失敗只顯示已量測elapsedMs，不宣稱整批完成。

酒精參考asset來自MXIC_NCKU_demo_v4/ref_dataset/alcohol.set143.k150.fasta，SHA-256為0bc77278d47ddcf41f1bbf4ef6f879d47f86c2d06791c0e29c5c0812a72b73f9，原始bytes未改動。143筆是77個位點的等位查詢，例如rs1229984有T_C、T_A、T_G；完整header區分query id，原始順序／序列／REF／ALT保留。每列使用獨立二等位模型，不是多等位聯合GT，不能加總同位點的各列深度或當成143個獨立SNP。只有參考查詢內建，個人combined資料仍直接讀USB。

## Debug 分段計時

時間單位ms，量測的是單調時鐘經過時間，不是CPU使用時間。整批包含USB開檔／大小及seek檢查（setupIoMs）、C實際索引／posting讀取與metadata探測（queryIoMs）、扣除I/O後的SNP查詢／去重／計數（countMs）、C beta-binomial（genotypeMs）、其餘橋接／控制／結果處理（overheadMs）、totalMs。每列另有ioMs、countMs、genotypeMs、nativeOverheadMs及nativeTotalMs。分解不得重複累計；Dart拒絕非有限／負值、分解或逐列加總不一致的時間。

totalMs从worker開始到結果結構建置完成，不含排程等待、Flutter渲染、剪貼簿、logcat及FD關閉cleanup。I/O包含provider與系統cache，不等同實體USB磁碟耗時；計數阶段含查詢控制／取消檢查，並非CPU profiler。debug關閉時不做逐讀取clock量測；開啟本身有量測開銷，快取也會影響重跑結果，不能據此承諾某一手機的效能。

啟用debug才會輸出GeneEdgeSnp logcat摘要，每行有界並escaped，不含序列、原始read ID、source URI或檔案內容；報告schemaVersion=1含set版本、各列結果及計時。這些摘要仍是敏感基因資訊，複製會進剪貼簿，日誌可能被偵錯工具看到；不自動保存、上傳或呼叫LLM。

## Pixel／真實USB驗收

1. 開啟手機SNP運算、選酒精set，確認77位點／143查詢、版本及載入成功；授權並選定真實USBpair，不使用舊匯入入口。
2. 開啟debug、開始，確認UI仍可取消；完成應143/143、143列與相同set版本。複製報告核對各階段總和，no-call為研究模型結果，不等於讀取失敗。
3. 關閉debug再跑，對照計數、posterior與GT完全一致；分段報告與新增基因結果日誌應不出現。重跑快取不同時不可直接把时间差歸因於演算法。
4. 運算中按取消、另次運算中拔除USB，確認不出現完成結果／舊報告；重新接入後重新掃描與選來源。
5. 用已知人工fixture或獨立桌面C核對選定query的counts，再驗證模型；沒有真實GT時不宣稱生物判定正確。記錄手機、set版本、USB來源、結果／錯誤、記憶體與分段時間。

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
- debug／set修改前Git備份：c1c038e3cf788a304a0677031edb9e420fc7a9e0，遠端分支codex/backup-before-snp-debug-20260930，已核對遠端SHA。
- Native tests：snp_engine_test.c涵蓋跨4GiB／40bit、去重、58/59邊界、取消、錯誤及上限；genotype_model_test.c涵蓋獨立機率參考與數值邊界；snp_pipeline_test.c人工42 reads fixture含20REF／20ALT／1ambiguous／1coverage-only，驗證模型depth40及0/1。
- Native以C99、warnings-as-errors及UndefinedBehaviorSanitizer驗證。Apple本機AddressSanitizer在main前初始化卡住，未取得ASan驗證通過。
- 本次Flutter完整58測試通過，flutter analyze無問題，涵蓋酒精143筆流程、debug顯示／剪貼簿、取消與stale抑制；完整流程fake platform測試禁止HTTP，並非實機USB結果。Android SNP15項與USB10項通過。Android完整suite先前有既有BlueMagpie ModelManifestParserTest權重大小不一致，未改動該模組，不能稱完整Android suite全綠。
- JVM host harness呼叫真正JNI bridge、C計數與C模型，驗證跨4GiB人工fixture、JSON欄位、ZERO_DEPTH、0/1、取消100次、Java callback例外及caller FD仍有效。此harness不是Android實機測試；Mac JVM不能載入UBSan dylib，因此JNI測試使用一般warnings-as-errors建置，C測試另以UBSan驗證。
- 2026-09-30 ARM64 debug APK已建置，以adb install -r成功更新到Pixel 10 Pro並啟動，保留原有App資料。真實USB seek、取消／拔除、記憶體、耗時與結果對照仍待驗收；不得把安裝成功或設計fixture當真實患者運算驗證。
- 尚未新增LLM傳輸；結果只在本機頁面顯示。不能宣稱整條到LLM的實機流程完成。
