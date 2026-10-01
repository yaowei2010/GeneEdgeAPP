# 手機 USB 離線 SNP 運算

聊天室新版的四等位聯合計數與 Dirichlet-multinomial genotyping 均使用 C；Flutter 只管理輸入／畫面／JSON轉換，Kotlin／JNI 只管理 USB 權限、FD 與工作生命週期。原本獨立頁的二等位 beta-binomial 模式保留。AI URL API 未修改，不自動把研究結果送至 LLM。

## 操作

1. 插入 USB，在原本聊天室選「酒精」主題。既有上方下拉設定的標頭顯示 USB 圖示，收合時仍可見；就緒是綠色並顯示「USB 已就緒」，未授權／未選／set未就緒則顯示待設定文字與橘色。不需要USB離線模式開關、不切換聊天畫面、不需完成舊匯入；插入本身不開始計算。
2. 滑鼠停留或手機長按 USB 圖示，提示已選定的可讀資料夾名稱與就緒狀態，不顯示內部ID／SAF URI；多組未選時只提示待授權或選取，不猜第一組。點擊圖示或原設定按鈕展開同一個上方下拉區，查看set、來源授權與debug；內容可捲動，鍵盤開啟時高度受限，訊息流不再放常駐來源設定卡片。首次授予資料夾唯讀權限；來源必須是掛載removable UUID，拒絕手機primary儲存。需同目錄精確雙檔combined_idx_all.txt與combined_ids_all.txt；單一來源沿用自動選定，多組時自行選擇。提示／展開均不計算；失效清除舊資料夾提示，掃描確認無USB後移除圖示。
3. 原主題自動帶入set，確認143筆參考／77位點、版本alcohol-set143-k150-v1。USB存在但未授權、多組未選、主題無set、載入未完成或失敗時送出不可用，不改走BLE／Local JSON／雲端。沒有USB時原本聊天路徑不變。
4. 若需耗時，先在展開操作啟用「Debug：結果與分段計時」（預設關閉）。直接在原輸入框輸入問題並送出，以文字／主題／set／來源／debug快照執行C；訊息流顯示本次使用者泡泡及計算回覆，原聊天泡泡保留。進度到77/77，工作中锁定主題／來源／debug與重送，可取消。
5. 同訊息流的完成卡片包含每位點唯一GT或no-call、四類計數、10候選posterior，以及debug啟用時的分段時間。展開API JSON或按「複製 API JSON」；debug關閉仍可取得JSON。複製是顯式操作，基因資訊會進剪貼簿。
6. USB文字／結果是暫存UI，不寫聊天歷史、不自動TTS／HTTP／LLM；只保留最新USB工作的一組訊息，下一次送出替換。取消、拔除、變更來源／主題、登出使成功結果與匯出失效，晚到事件不可還原，失敗不自動改送網路。取消／失敗只顯示已量測elapsedMs，不宣稱完成。

側欄「手機 SNP 運算」保留為進階／legacy工具，單SNP與外部FASTA仍支援301bp、最多3000筆及2MiB限制；該頁酒精set執行143筆獨立二等位查詢、進度143/143，不是聊天室77位點聯合判定。

酒精參考asset來自MXIC_NCKU_demo_v4/ref_dataset/alcohol.set143.k150.fasta，SHA-256為0bc77278d47ddcf41f1bbf4ef6f879d47f86c2d06791c0e29c5c0812a72b73f9，原始bytes未改動。143筆是77個位點的等位查詢，例如rs1229984有T_C、T_A、T_G；完整header／原始bytes保留。聊天室依rsID、染色體、位置分組，驗證共同REF及300bp側翼，四種中心鹼基共用read去重表，不加總獨立ALT查詢的REF深度。只有參考查詢內建，個人combined資料仍直接讀USB。

## API JSON

純serializer沿用ApiService.askLlm欄位；user_id取llmUserId非空值，否則threadId，query／中文topic取工作快照。以下是示意資料，不是實測：

```json
{"user_id":"example","query":"我能喝酒嗎","topic":"酒精","SNP_list":["rs1229984-TC"],"snp_list":["rs1229984-TC"],"variants":["rs1229984-TC"],"variant_input_count":77,"variant_used_count":1,"no_call_count":76,"yuguard":null}
```

三份variant列表相同，GT indices轉成實際鹼基並保留REF優先排序，不包含斜線。同位點只一筆；no-call不放入API列表，仍留在診斷。重複rsID跨座標拒絕匯出。診斷schemaVersion=2另外包含jobId、set／模型版本、全部位點結果及可選debugTiming，不把URI、read ID、序列或診斷欄位混進API request。沒有新增自動傳輸或保存。

## Debug 分段計時

時間單位ms，量測的是單調時鐘經過時間，不是CPU使用時間。整批包含USB開檔／大小及seek檢查（setupIoMs）、C實際索引／posting讀取與metadata探測（queryIoMs）、扣除I/O後的SNP查詢／去重／計數（countMs）、C模型（genotypeMs）、其餘橋接／控制／結果處理（overheadMs）、totalMs。每列另有ioMs、countMs、genotypeMs、nativeOverheadMs及nativeTotalMs。聊天室重新量測77個聯合位點，不加總legacy143列時間。分解不得重複累計；Dart拒絕非有限／負值、分解或逐列加總不一致的時間。

totalMs从worker開始到結果結構建置完成，不含排程等待、Flutter渲染、剪貼簿、logcat及FD關閉cleanup。I/O包含provider與系統cache，不等同實體USB磁碟耗時；計數阶段含查詢控制／取消檢查，並非CPU profiler。debug關閉時不做逐讀取clock量測；開啟本身有量測開銷，快取也會影響重跑結果，不能據此承諾某一手機的效能。

啟用debug才會輸出GeneEdgeSnp logcat摘要，每行有界並escaped，不含序列、原始read ID、source URI或檔案內容；聊天室報告schemaVersion=2（legacy為1）含set版本、各列結果及計時。這些摘要仍是敏感基因資訊，複製會進剪貼簿，日誌可能被偵錯工具看到；不自動保存、上傳或呼叫LLM。

## Pixel／真實USB驗收

1. 在原聊天室選酒精主題、插入USB，確認上方標頭USB圖示、長按資料夾提示及就緒／待設定文字；展開上方設定確認77位點／143參考，必要時授權與來源選擇。不能有離線開關或換掉原訊息流，原聊天泡泡應仍可查看；不使用舊匯入入口。
2. 開啟debug、輸入問題並送出，確認UI仍可取消；完成應77/77、77列與相同set版本。核對API三份列表一致、每rsID唯一、input77、used加no_call等於77；複製診斷核對各階段總和，no-call不等於讀取失敗。
3. 關閉debug再跑，對照計數、posterior與GT完全一致；分段報告與新增基因結果日誌應不出現。重跑快取不同時不可直接把时间差歸因於演算法。
4. 運算中按取消、另次運算中拔除USB，確認不出現完成結果／舊報告；重新接入後重新掃描與選來源。
5. 用已知人工fixture或獨立桌面C核對位點四類counts、跨ALT去重與10候選posterior；total=四類counts+ambiguous+coverageOnly。驗證登出／主題切換清空、一般聊天未改動。沒有真實GT時不宣稱生物判定正確。記錄手機、set版本、USB來源、結果／錯誤、記憶體與分段時間。

新計算入口直接按索引唯讀 USB，不完整複製 combined 檔案。原本 USB 匯入入口仍保有256MiB每檔上限，不能匯入真實大型pair；請使用新計算入口。USB provider 若不支援 seek，回報 NOT_SEEKABLE，不增加寫入權限或改用全檔複製。

## C 計數

IDX 必須為536870912 bytes，IDs非空且四byte對齊。little-endian IDX每桶八byte，posting位置40bit、count24bit；IDs每筆uint32 read ID。C 使用64bit pread，檢查範圍並分批讀取。

K13、step2，同時比較中心 REF／ALT 及反向互補；背景位置不雙算，posting重複不雙算。每方向的匹配位置數大於58才支持分類。完整read ID（含R1/R2來源bit）在兩方向合併後只計一次，R1與R2不宣稱已合併成獨立fragment。REF／ALT支持較高者歸類，平手且非零為ambiguous；皆零為coverage-only。total=REF+ALT+ambiguous+coverageOnly。

聊天室對A/C/G/T四種中心與反向互補使用共同read表，背景coverage只累計一次；同一read／位置／方向去重。coverage>58方向的唯一最大正支持決定鹼基，正支持並列為ambiguous，皆零為coverageOnly。total=sum(baseCounts)+ambiguous+coverageOnly，effectiveDepth=sum(baseCounts)。外部alleles排序為REF在前，其餘依A/C/G/T，posterior按i<=j列出10組。

posting桶大於65536則跳過並回報skippedBuckets，不補造支持數。候選read上限100萬，超限報 RESOURCE_LIMIT，禁止截斷後成功。共同四等位稀疏表最多約72MiB，rehash時約108MiB；legacy二等位表48MiB／72MiB，另有批次buffer與UI結果。這是設計上限，不是Pixel量測值。

與demo差異：修正獨立read去重／尾端漏計風險、不累加同一read的兩方向depth、不補造被跳過桶的coverage、不使用dense10GiB陣列；因此不宣稱輸出与原始demo逐位相同。以人工fixture驗證，不以demo的疑似錯誤作真值。

## 研究模型

聊天室版本dm-locus-research-v1，calibrated=false。對A/C/G/T計數枚舉10種二倍體候選；每鹼基dosage d為0、0.5或1，mu=d*(1-epsilon)+(1-d)*epsilon/3，concentration=1/rho-1，alpha=mu*concentration。以Dirichlet-multinomial log likelihood加prior，log-sum-exp正規化，選最大後驗。預設epsilon=.01、rho=.02、10個prior各.1、minDepth10、minPosterior.99。零／低深度、最佳兩候選log score差<=1e-12或posterior不足門檻均no-call；保留bestGenotype、bestPosterior、logScoreGap與全部posterior，不用其他ALT當fallback。這些是未校準研究假設，沒有BQ／MQ，不是GATK、不能視為真實GT機率或臨床結果。

以下是保留的進階／legacy二等位模型：

版本bb-research-v1，calibrated=false。有效深度n=REF+ALT，不包含ambiguous／coverage-only。各基因型 ALT 比例均值為epsilon、0.5、1-epsilon；concentration=1/rho-1；alpha=mu*concentration，beta=(1-mu)*concentration。計算beta-binomial likelihood加prior，用log-sum-exp正規化posterior。

固定研究預設：epsilon=0.01、rho=0.02、prior=(1/3,1/3,1/3)、minDepth=10、minPosterior=0.99。這些是尚未校準的假設，不是原始Base Quality。C接口拒絕非法／非有限參數：epsilon須在[1e-6,0.5)，rho在[1e-6,1-1e-6]，prior各自正且總和1（容差1e-9），有效depth最多100萬。

GT輸出0/0、0/1、1/1；零深度、低深度、最高posterior低於門檻或並列則./.，保留原因與posterior。此版不是GATK HaplotypeCaller等效，也非臨床判讀。k-mer evidence與BAM計數不同，R1/R2可能相關；需要已知GT資料校準與外部驗證後才能解讀信心。

## 驗證與限制

重跑C與JNI驗證：bash scripts/test_snp_native.sh。此命令只產生暫存測試binary／人工fixture，不讀USB個人資料、不連網。Flutter：flutter test、flutter analyze。Android：在android目錄執行 ./gradlew :app:testDebugUnitTest --tests 'com.example.geneapp.snp.*' --tests 'com.example.geneapp.usb.*' -PbluemagpiePoc=false。APK：flutter build apk --debug --target-platform android-arm64。

- 原版Git備份：457fba7，遠端分支codex/backup-before-mobile-snp-20260930。
- USB圖示修改前備份：2ad0a2d23b6b802db34a434c608c121bdb82ffe9，遠端分支codex/backup-before-usb-icon-20261001，已核對遠端SHA。包含已安裝原訊息流版的提交歷史；本次備份提交只新增四個相關規格檔的追加內容，不含其他功能或USB個人資料。
- debug／set修改前Git備份：c1c038e3cf788a304a0677031edb9e420fc7a9e0，遠端分支codex/backup-before-snp-debug-20260930，已核對遠端SHA。
- 聊天室／joint修改前Git備份：8f0ef03a3fcc3ea7506aa27e860492bafabed701，遠端分支codex/backup-before-locus-chat-20260930，限定23個相關檔案且遠端SHA已核對。
- 原聊天室訊息流修正前Git備份：ce71eef62bd501a1bfa76ff588bb1c94f95fadcf，遠端分支codex/backup-before-usb-chat-flow-20261001，限定28個相關檔案且遠端SHA已核對，不含其他變更或USB個人資料。
- Native tests：snp_engine_test.c涵蓋跨4GiB／40bit、去重、58/59邊界、取消、錯誤及上限；genotype_model_test.c涵蓋獨立機率參考與數值邊界；snp_pipeline_test.c人工42 reads fixture含20REF／20ALT／1ambiguous／1coverage-only，驗證模型depth40及0/1。
- Native以C99、warnings-as-errors及UndefinedBehaviorSanitizer驗證。Apple本機AddressSanitizer在main前初始化卡住，未取得ASan驗證通過。
- 前次joint版Flutter70項、Android SNP17項與USB10項通過。2026-10-01介面修正版Flutter75項通過、flutter analyze無問題、native／JNI回歸通過；涵蓋原訊息流保留、插入不自動計算、送出77位點、未授權／多來源／載入錯誤阻擋、JSON／debug、取消／拔除／登出與stale抑制，禁止HTTP／聊天持久化，非實機USB結果。本次未改Android/C演算法；Android完整suite先前的BlueMagpie ModelManifestParserTest權重大小不一致未改動，不能稱完整Android suite全綠。
- JVM host harness呼叫真正JNI bridge、C計數與C模型，驗證跨4GiB人工fixture、JSON欄位、ZERO_DEPTH、0/1、取消100次、Java callback例外及caller FD仍有效。此harness不是Android實機測試；Mac JVM不能載入UBSan dylib，因此JNI測試使用一般warnings-as-errors建置，C測試另以UBSan驗證。
- 新增snp_locus_test.c驗證四等位共同去重、partition、雙方向、40bit／超4GiB、58/59邊界、取消與上限；locus_genotype_model_test.c以獨立long double計算核對10候選posterior、全部GT含C/G、低深度／並列／參數錯誤。JNI新增joint77列、debug on/off結果一致、caller FD所有權與逐位點分解驗證。上述均為人工fixture。
- 前次「原聊天室USB送出」版已依使用者要求install -r成功安裝至Pixel 10 Pro並啟動。2026-10-01最新「上方USB圖示／下拉設定」版ARM64 debug APK位於build/app/outputs/flutter-apk/app-debug.apk，已依使用者要求以install -r安裝至Pixel 10 Pro（61210DLCH001H5），回傳Success；MainActivity啟動成功且確認APP程序存在，保留原APP資料。真實USB seek、取消／拔除、記憶體、耗時與結果對照仍待驗收，tasks3.3保持未勾選；不得把建置／安裝或人工fixture當真實基因資料正確性驗證。
- 最新圖示版採測試先行：先確認缺少USB圖示而失敗，再完成實作。Flutter全套76項通過、analyze無問題；新增hover／long-press、上方設定雙入口、鍵盤捲動無overflow、舊tooltip失效、多來源不猜與不自動計算測試。本次沒有更動C／Android演算法，這些為widget／fake驗證，不是真實USB計數效能量測。
- 尚未新增LLM傳輸；結果與可用JSON只在本機聊天室顯示。不能宣稱整條到LLM的實機流程完成。
