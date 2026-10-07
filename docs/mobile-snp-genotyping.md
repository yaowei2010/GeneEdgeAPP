# 手機 USB 離線 SNP 運算

聊天室新版的四等位聯合計數與 Dirichlet-multinomial genotyping 均使用 C；Flutter 管理輸入／畫面／JSON轉換與既有LLM串接，Kotlin／JNI 只管理 USB 權限、FD 與工作生命週期。原本獨立頁的二等位 beta-binomial 模式保留且不送LLM。聊天室GeneLLM開啟時，合法USB聊天完成後會沿用原APP的ApiService.askLlm及既有URL/v1/ask送API JSON，接收response顯示於同一聊天室；不更動server契約或C模型。

## 操作

GeneLLM可直接在USB上方表單確認：插入USB後，點聊天室上方「開啟設定」（調整圖示）展開原下拉表單，最上方就是「GeneLLM」開關。副標題「LLM ON」代表完成USB計算後會送既有LLM，「LLM OFF」代表只離線計算；與左側選單GeneLLM on／off同步，沿用原ChatController偏好、不新增USB專用開關紀錄。C計算或等待LLM期間，這個表單開關暫時停用；JSON顯示仍可切換。單純展開或切換不開始運算、不HTTP，也不補送先前完成的离線JSON，只有下一次聊天送出才使用新的設定。

1. 在前景聊天室插入 USB（或開聊天室時已有 USB），自動顯示「USB 使用確認」，不必點選酒精或切換主題，也不等待SNP set／來源掃描完成；掃描中會顯示「USB 來源掃描中」且不可確認計算。其他頁面或APP非前景時不強制彈窗，返回前景聊天室且idle才處理仍掛載的新USB。可用關閉、取消、返回或點外部關閉，同次插入不反覆彈出；關閉後仍顯示上方 USB 圖示，但不能送出 USB 計算。點圖示可重開；點「使用此 USB」只確認來源，插入、授權、確認都不開始計算。
2. 確認頁預設位置是「USB 根目錄」。已有有效唯讀授權先沿用；首次或需要擴大範圍時按「授權 USB 根目錄」，系統選擇器預選該 USB 最外層，仍須親自確認授權，APP 不代按。若 provider 限制根目錄，依實際允許資料夾授權；舊子資料夾權限會明示「子資料夾」，不冒充根目錄。只讀掛載 removable UUID，不讀手機 primary。授權範圍內搜尋同目錄精確雙檔 combined_idx_all.txt 與 combined_ids_all.txt，維持深度16／10000項限制。保存唯讀grant與來源URI metadata，不保存基因資料；重新插入恢復同USB仍有效的來源，否則只有唯一pair才自選，多USB／多組未選不猜。
3. 滑鼠停留或手機長按 USB 圖示，提示可讀資料夾名稱與狀態，不顯示ID／SAF URI。未確認顯示「USB 待確認」，確認且set ready才顯示綠色「USB 已就緒」。原設定箭頭仍展開上方set／來源／debug，內容可捲動且鍵盤開啟高度受限。選「酒精」自動带入143筆參考／77位點、版本alcohol-set143-k150-v1；USB未確認、未授權、多組未選、無set或載入失敗時送出不可用，不改走BLE／Local JSON／雲端。拔除、來源變更或登出清除使用確認，授權晚到不能恢復已拔除來源；沒有USB時原聊天路徑不變。
4. 若需耗時，先在展開操作啟用「Debug：結果與分段計時」（預設關閉）。直接在原輸入框輸入問題並送出，以文字／主題／set／來源／debug快照執行C；訊息流顯示本次使用者泡泡及計算回覆，原聊天泡泡保留。進度到77/77，工作中锁定主題／來源／debug與重送，可取消。
5. 同訊息流的完成卡片只顯示完成狀態、API JSON與「複製 API JSON」，正文高度有界可捲動，不再展示77張位點／posterior明細或debug全文。上方設定的「顯示 API JSON」預設開啟，可隱藏現在及下次結果，隱藏後只留「已完成，API JSON 已隱藏」；重開APP沿用偏好，但不恢復舊基因結果。只保存snp_chat_show_api_json boolean；偏好尚未載入／格式錯誤時不顯示正文。開關只影響畫面，不重算、不傳API、不自動複製，也不改debug。隱藏不是加密或刪除記憶體，不能清除之前自行複製的剪貼簿或已啟用debug的logcat。
   若本次計算啟用了debug，上方設定提供「查看 debug／分段計時」，主動開啟有界可捲動的診斷視窗，含每位點計數／候選posterior、研究警示、階段時間與「複製 debug 結果」；debug off沒有報告。結果失效會關閉診斷。複製始終是顯式操作，基因資訊會進剪貼簿。
6. 在送出前開啟原本「GeneLLM」，並確認APP既有server URL可由手機網路存取。送出時固定捕捉開關狀態；ON會等完整C結果後送出一次API JSON（77位點、三份一致且排除no-call的variantlists），顯示「等待 LLM 回覆…」後將server answer放在原聊天泡泡中；OFF只做離線結果。計算中切換GeneLLM不改本次快照。隱藏API JSON只影響正文，不阻止已啟用的LLM請求、不隱藏answer，切換顯示不重送。API請求不含debug診斷、posterior、序列、read ID或URI，且USB路徑固定關閉原LLM request debuglog，不把基因request輸出聊天debug泡泡或寫檔。
7. LLM等待時鎖定重送、主題與來源／debug操作；失敗顯示安全錯誤與「重試 LLM」，C結果仍有效。只有有效結果且GeneLLM開啟才能手動重試同一request，不重跑C、不自動重試，也不改用BLE／mock。可「取消等待 LLM」使結果失效；已傳至server的request不能撤回，只忽略其晚到回覆。取消、拔除、來源／主題變更、登出或離開頁面清除本次輸出與retry，晚到成功／失敗不能復活舊結果或影響新工作。USB文字／JSON／診斷／LLM回覆仍只保留最新一組暫存UI，不寫聊天歷史、不自動TTS；下一次送出替換。原沒有USB時的普通／BLE聊天保存行為不變。取消／C失敗只顯示已量測elapsedMs，不宣稱完成、不HTTP fallback。

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

LLM串接新版另驗收：確認手機可達既有server URL，開GeneLLM→插USB／確認來源→選酒精→輸入問題。確認C到77/77後才顯示等待LLM，server response在同一聊天室泡泡呈現；關閉JSON仍有answer且server只收到一份request。GeneLLM OFF時不送server。斷網或server失敗需看到「LLM 回覆失敗」及「重試 LLM」，恢復網路後只重送同JSON而不重跑C；等待時拔USB／取消／切主題／登出，遲到回覆不可出現在新工作。實際server日誌、PixelUSB流程與計數／效能必須另量測，mock HTTP測試不能替代。

1. 在原聊天室選酒精、插入USB，確認自動出現可關閉視窗；取消／返回／點外部後不反覆彈出且不能送出，點上方USB圖示重開。首次根目錄授權檢查系統picker預選USB最外層，再手動同意；拔插後檢查有效grant與來源恢復、不必再挑資料夾，但仍須「使用此 USB」。舊子目錄grant應明示實際範圍，多來源未選不能送出。長按查看資料夾，設定箭頭展開77位點／143參考及debug；原聊天泡泡保留，不使用舊匯入入口。
2. 不點主題先插入USB，確認立即彈窗；再選酒精／確認来源，開啟debug、輸入問題並送出，確認UI仍可取消。完成應77/77且聊天室只顯示有界API JSON；關閉「顯示 API JSON」後當前與下次正文皆不可見，重開APP偏好仍關閉但不恢復舊結果，重新顯示不重算。核對API三份列表一致、每rsID唯一、input77、used加no_call等於77；由上方「查看 debug／分段計時」核對77列、set版本與時間加總，拔除／切主題後診斷失效。no-call不等於讀取失敗。
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
- USB確認修改前備份：74a3ca8c31589a4c1202f5ee4389200a4fb086a3，遠端分支codex/backup-before-usb-confirm-20261001，已核對遠端SHA；限定已安裝圖示版及本次相關規格共8個檔案，不含其他功能或USB個人資料。
- 插入即確認／精簡JSON修改前備份：5e05c6bd096169907318f87aaf6eb3361c1dfdb5，遠端分支codex/backup-before-usb-json-20261001，已核對遠端SHA；限定已安裝確認版及本次相關規格共13個檔案，不含其他功能或個人USB資料。
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
- 2026-10-01最新確認版Flutter全套87項、Android SNP19項／USB10項通過，flutter analyze無問題，ARM64 debug APK建置成功（build/app/outputs/flutter-apk/app-debug.apk）。新增取消／返回／點外部與重開、授權返回去重、多USB／子資料夾範圍、根目錄授權重用、未確認阻擋送出、拔除／關閉後late回覆拒絕、鍵盤與dispose測試。Android純契約測試涵蓋root URI定位／primary拒絕、目前來源／同卷記錄／唯一pair恢復順序及失效拒絕；實際SAF picker初始定位、系統保存grant與重插仍需Pixel驗收。本版未改C模型或API；已依使用者要求以install -r安裝至Pixel 10 Pro（61210DLCH001H5），回傳Success，MainActivity冷啟動Status: ok且APP程序存在，保留原APP資料。不把安裝成功或fake／單元測試當實機授權或基因驗證，3.3保持未完成。
- 舊版僅產生本機JSON；本次新增GeneLLM ON的完成後傳輸及聊天室response。自動化fake API與mock HTTP不代表實際LLM server或Pixel整條流程已驗收。
- 2026-10-01最新「插入即確認／精簡JSON」版：測試先行重現掃描中未通知掛載／其他路由返回漏提示／非前景彈窗、掃描中仍可確認與拔除後late掃描回覆，以及舊位點明細仍佔位。新增先通知volumes再掃描、獨立於主題／set的排程與返回前景處理；新增JSON隱藏boolean、late偏好保護、正文／語意移除、下次工作與重開頁偏好，以及主動診斷／取消／拔除／主題／登出／dispose回歸。Flutter全套102項通過、flutter analyze無問題、Android SNP19項／USB10項通過，ARM64 debug APK建置成功（build/app/outputs/flutter-apk/app-debug.apk）；未修改C模型／API serializer。已以adb install -r更新至Pixel 10 Pro（61210DLCH001H5），回傳Success，保留既有APP資料；MainActivity冷啟動Status: ok，確認程序執行中（PID 23071）。這些測試與安裝確認不等同Pixel真實掛載或SAF定位、計數／效能驗收，3.3保持未完成。
## USB → LLM 串接備份

2026-10-01 後續表單版安裝：依使用者要求，以adb install -r將含USB上方GeneLLM開關的ARM64 debug APK更新至Pixel 10 Pro（61210DLCH001H5），回傳Success且保留原APP資料；MainActivity啟動Status: ok，確認程序執行中（PID 25084）。此紀錄更新下方建置時「尚未安裝此版」狀態；不代表真實USB／LLM server流程已驗收，3.3仍未完成。

2026-10-01 USB表單GeneLLM版驗證：先以widget失敗測試確認表單尚無開關，再新增沿用controller setter的頂端SwitchListTile。新增4項測試驗證兩入口同步／原偏好恢復、開關不計算或HTTP／不補送舊JSON、下一次送出傳送、C／LLM busy禁用且JSON顯示獨立、鍵盤開啟有界及缺callback禁用。Flutter全套132項通過、flutter analyze無問題，ARM64 debug APK建置成功（build/app/outputs/flutter-apk/app-debug.apk）；git diff --check與Spectra validate通過，規格分析無Warning／Critical。未改C／Android或LLM契約，尚未安裝此版Pixel；mock／widget不等於實機USB／server驗收，3.3保持未完成。

2026-10-01 USB表單GeneLLM開關修改前，已將目前Pixel已安裝LLM版及追加規格限定10個相關檔案備份至遠端 `codex/backup-before-usb-llm-toggle-20261001`；commit `88574070381e96b621ba7df70de2590bcec34c79`與git ls-remote一致，未包含其他功能與個人USB資料。

2026-10-01 後續安裝：依使用者要求，將USB接既有LLM版ARM64 debug APK以adb install -r更新至Pixel 10 Pro（61210DLCH001H5），回傳Success並保留原APP資料；MainActivity啟動Status: ok，確認程序執行中（PID 23907）。這僅確認安裝／啟動，尚未驗收手機真實USB→實際LLM server→聊天回覆，3.3保持未完成。

2026-10-01 串接前已將目前Pixel精簡JSON版及本次規格限定備份至遠端 `codex/backup-before-usb-llm-20261001`，commit `a4d557888781a50568bbe815b6ccb6b722882d5f`；已核對遠端SHA與11個相關檔案清單，未包含其他功能或個人USB資料。回退可從此commit重建APK並更新安裝，無需清除APP資料。

2026-10-01 USB接既有LLM版驗證：先以失敗controller／widget測試確認USB入口及完成後request尚未存在，再實作askCompletedUsb與原聊天室暫存response。新增26項測試涵蓋77/70/7、全部no-call、既有ApiService的POST URL／exact JSON及answer／choices解析、GeneLLM送出快照、hidden JSON不重送、等待single-flight、HTTP安全失敗／顯式retry、C未完成不HTTP、取消／拔除／來源／主題／登出／dispose遲到成功與失敗抑制及舊finally不清除新工作。Flutter全套128項通過、flutter analyze無問題；ARM64 debug APK建置成功（build/app/outputs/flutter-apk/app-debug.apk），git diff --check及Spectra validate通過，規格分析無Warning／Critical。未改C／Android模型或server API，未重新安裝Pixel、未呼叫實際LLM server驗收；3.3真實USB對照／效能保持未完成。
