## Context

現有 USB 功能採 SAF 唯讀授權並匯入私有儲存，每檔上限 256 MiB。真實 IDX 為 512 MiB，IDs 約 28.1 GiB，手機運算不能依賴此匯入。原始 C 採約 10 GiB dense counters 並由 Python 以門檻判定基因型；本變更以獨立 C 引擎替換兩者。

## Goals / Non-Goals

Goals：直接讀 USB、Flutter 呼叫 C、去重 SNP 計數、獨立 beta-binomial 模型、可取消與可追溯結果。
Non-Goals：手機內部 combined 資料、複製完整 USB 資料、FASTQ 建表、GATK／PairHMM 等效、品質分數推造、臨床認證、改變 AI API。

追加範圍：debug mode 的結果顯示／複製、logcat 摘要與單調時鐘分段計時；不包含背景持續監控、原始 reads 輸出、自動保存／上傳或改變計數與模型判定。

追加範圍：以原本 App 主題語彙呈現 SNP set 選單、內建酒精143筆參考查詢，以及從 set 選取到離線結果的測試。不把聊天主題本身當成 SNP 資料，不捏造尚未提供的 set，也不新增自動 LLM 串接。

## Decisions

### USB結果沿用既有LLM功能

本節及對應Implementation Contract是最新優先契約，取代前LLM界線與禁止HTTP的舊聊天室描述；已完成task保持歷史記錄，獨立計算頁仍不送LLM。範圍內是USB結果銜接既有雲端API與暫存聊天回覆；範圍外是新server／HTTP client、BLE／mock重算、C模型／序列讀取變更、診斷上傳、基因資料持久化、自動TTS及背景重試。

沿用`ChatController`的GeneLLM開關與`ApiService.askLlm`傳送／response解析，提供明確USB完成結果入口，不呼叫會再次啟動BLE或Local JSON的`sendUserMessage`。呼叫端只接受`SnpApiPayload.fromCompleted`產生的完整有效request，使用其user_id／query／topic／三份variants及原始位點／成功／no-call計數、yuguard；不能從目前snpList／聊天歷史覆蓋快照或將77個位點誤算成70個成功call。主題沿用現有中文契約與既有cloud正規化規則，不新增名稱映射。傳輸debug固定false，不把request／variants寫入原API debug檔或debug聊天泡泡。回覆解析與雲端錯誤處理重用現有功能，不將JSON或完整posterior當聊天answer。

送出時固定GeneLLM啟用狀態及USB工作context。未開啟時只顯示離線JSON、不在完成後切開關自動傳送；開啟時完成事件自動發送一次。完成通知能重複，必須以resultJobId與generation去重並single-flight；原生runLoci回傳是啟動工作，不代表工作完成，不能立刻HTTP。C執行及LLM等待期間阻擋重複送出；上方JSON顯示可切換且不重算／重送。等待與answer／安全錯誤泡泡接在該暫存USB使用者訊息及JSON卡片後，沿用既有_Bubble渲染，不建立獨立聊天室、不持久化request／回覆。HTTP失敗不改成功的C結果，明示LLM失敗與「重試 LLM」；只有結果仍有效且GeneLLM開啟才可主動重試同一快照，不重跑C，不自動重送。

取消、USB拔除／來源失效、主題切換、登出或dispose使generation失效並清空pending／answer／retry。HTTP已送出的資料無法撤回，現有ApiService沒有abort能力時只能忽略遲到response且不得顯示於其他主題／工作；文件必須明說此限制。新工作不能被舊finally清除busy。未授權、未確認、無set、部分／非法／取消結果不HTTP；無USB原sendUserMessage不變。空variants但77個完整no-call結果仍依現有askLlm契約傳空list，不能悄悄fallback一般SNP。

### 插入即確認與精簡JSON

此節優先於下面已完成的聊天室結果明細展示契約。前景聊天室偵測mounted removable USB時，未選主題、主題無set、set載入中／失敗皆須彈出USB確認，不能等待主題選擇的setState才處理。先以controller／widget及Android事件流程檢查掛載通知、discover／scan、post-frame排程與路由就緒；修正實際造成延遲的環節，必要時使已確認掛載的volumes狀態先於來源掃描完成通知，避免大型USB掃描阻塞確認。不得用自動選酒精掩蓋問題，不新增背景輪詢服務；畫面返回前景須重新核對掛載狀態。已確認掛載、尚未找出pair時視窗顯示掃描／待來源，不冒充ready。保留同次掛載去重、關閉不重彈、圖示重開、busy延後到idle、拔除與late抑制，不在其他路由上強制彈窗；返回聊天室時仍掛載的新USB才處理。

`SnpChatResultCard`成功狀態只呈現API request JSON、簡短完成狀態與顯式複製操作，JSON區域有界可捲動，避免77位點輸出撑滿訊息流；不渲染77張明細、posterior列表或debug全文。上方既有設定新增「顯示 API JSON」開關，新安裝預設true，只在私有preferences保存boolean；載入完成前保守不展示正文，遲到的偏好載入不能覆蓋使用者剛切換的值。關閉時當前及之後成功卡片只留簡短「已完成，API JSON 已隱藏」，不將正文留在隱藏widget／語意節點；重新開啟僅展示仍有效最新結果，不重算／送API／自動複製。重開APP沿用偏好但不恢復基因結果。顯示偏好可在運算中切換，僅影響呈現，不改來源、主題、debug快照或job。

debug計算開關與C分段計時保持不變。若當前最新結果有debugReport，上方設定提供「查看 debug／分段計時」的顯式操作，開啟有界可捲動診斷視窗，內含研究警示、分段時間與顯式複製；debug off無報告。取消／拔除／來源或主題變更／登出／dispose清空結果並關閉失效診斷視窗，晚到事件不能恢復；不把診斷全文重新放回聊天卡片。

範圍內：前景掛載偵測時序、與set解耦的插入確認、精簡結果JSON、有界展示、顯示偏好及主動查看診斷、測試文件與修改前Git備份。範圍外：自動LLM／HTTP傳輸、改JSON欄位或C模型、基因資料持久化、自動系統授權、舊USB匯入重寫、背景監控。顯示隱藏不是加密或刪除記憶體結果；使用者主動查看／複製仍可見敏感資料。

### USB插入確認與根目錄授權恢復

此節為最新優先介面契約，追加可關閉的AlertDialog；USB圖示點擊改為重新開啟確認視窗，原設定箭頭仍展開上方來源／debug設定。初次進入聊天室已有掛載USB也視為一次插入，依掛載UUID集合辨識新裝置與拔除，重複refresh／set載入／系統授權返回不重複彈窗。對話框提供明確關閉／取消、Android返回及點外部關閉；同一次掛載關閉後不再自動彈出，重新插入才再顯示。多USB顯示可讀裝置選擇，不猜第一支；busy不開新的來源修改視窗，待idle後處理仍掛載的新裝置。拔除／logout／頁面dispose關閉相關視窗，post-frame與授權future使用掛載generation抑制晚到資料。視窗內容有界可捲動，鍵盤開啟不overflow。

確認頁預設顯示「USB 根目錄」；已有有效唯讀tree權限先沿用其實際範圍，若舊權限僅限子資料夾須清楚標示，另提供根目錄授權按鈕，不把子目錄冒充根目錄。未授權或需要改根目錄時，`requestAccess(volumeId)`建立該mounted removable UUID的root document URI（document id為UUID加冒號），在可用Android版本透過EXTRA_INITIAL_URI定位到USB最外層；不得自動按下系統授權或宣稱自動取得權限。provider限制根目錄選取時顯示限制／實際選定範圍，允許使用者確認可存取子目錄，不改用MANAGE_EXTERNAL_STORAGE、寫入權限或primary手機來源。保留takePersistableUriPermission唯讀保存及重新掛載valid檢查；只掃描目前合法tree，沿用SnpSourceScanner深度16／10000項與取消限制，同目錄精確combined双檔，根目錄未找到則搜尋授權子目錄。

原生discover先保留目前有效選擇，再恢復同UUID上次實際選定且仍在掃描結果內的pair，沒有有效紀錄時僅一組合法pair可自動選；多組無有效紀錄保持未選。將使用者明確選擇的來源metadata按UUID保存至專用私有preferences，不保存genotype、read、JSON或基因結果，不向UI／log顯示URI。紀錄不是權限來源，重新掃描、授權及掛載檢查每次都要通過；失效紀錄不得導向其他卷或手機。IPC原欄位保持相容，若需授權範圍metadata採可選欄位並驗證型別。

聊天室另記住每次掛載的使用確認，與系統已保存權限區分。關閉或取消不確認，不清除既有系統授權；USB仍可見但聊天送出保持阻擋，不fallback網路。點「使用此 USB」時只確認仍掛載、已授權且選定的來源，不runLoci；無來源／掃描中／授權失效／多來源未選顯示對應狀態。確認後只有合法文字及set ready時送出C；來源改變／拔除／logout清除相應確認與舊輸出，主題切換保留同USB確認但重新驗證set。

範圍內：插入／關閉／重開確認、root picker initial location、持久唯讀權限重用、來源metadata恢復、聊天室確認送出guard及測試。範圍外：自動代替系統授權、背景監控、自動C／LLM、個人combined複製、C模型與舊匯入重寫。採APP先確認再開系統picker，不在mount廣播強制開picker，避免使用者無法取消與重複彈出。

### USB偵測圖示與資料夾提示

此項為最新優先介面契約，取代「USB運算來源與原聊天訊息流」已完成版本的訊息列表來源卡片；送出路由／77位點模型／API契約不變。依使用者追加位置要求，全部USB操作整合到聊天室既有上方下拉設定區（_ExperiencePanel／_OperationsPanel）。偵測到removable volumes或sources時，在該區標頭呈現Icons.usb，使收合時也能辨識；未偵測時不顯示。已選定來源且set就緒用就緒色；待授權／未選／set未就緒用待設定色，語意與tooltip文字不能只依顏色區分。

使用Flutter Tooltip提供滑鼠hover與手機long-press提示。選定來源時由selectedSourceId對應sources.label取得可讀資料夾名，提示「USB・手機 C／資料夾：<label>」並附ready／set載入等狀態；不得以SAF URI／sourceId當資料夾名稱。沒有選定來源時提示「已偵測 USB，待授權或選取資料夾」，多組不能顯示任意第一組為已選來源。拔除或來源失效立即清除舊資料夾提示，確認無USB後移除icon。無USB時既有普通／BLE聊天不變。

點擊icon或原設定展開按鈕展開既有上方下拉區，沿用SnpChatControls的唯讀授權、來源選擇、set資訊及debug；不新增bottom sheet或独立AppBar入口、不切換聊天模式或導頁，不在訊息流放常駐大型設定卡片。展開內容須限制高度且可捲動，避免手機或鍵盤開啟時overflow；持續反映controller狀態，運算中授權／來源／debug禁用；USB拔除後不顯示過期選定資料夾。插入、hover、long-press、展開設定均不呼叫runLoci／HTTP，只有原composer送出合法文字且USB ready時才執行C。保留同訊息流的暫存使用者泡泡、進度／取消／結果與JSON。

範圍內：上方下拉設定的icon、tooltip、來源操作與widget驗證。範圍外：完整USB路徑解析、系統檔案管理器、原生模型／BLE／API改動、自動計算／自動上傳。選用tooltip而非觸碰才切模式，因為手機沒有hover、長按可提供相同資訊而不干擾聊天送出。

### USB運算來源與原聊天訊息流

2026-10-01優先修正契約：下面「聊天室離線流程與API JSON」的明確離線開關／切換body是上一版實作記錄，不再是新介面驗收。保留普通聊天室ListView、歷史泡泡、主題與composer。USB是類似BLE／Auto的實際運算来源，非另開工具畫面；Auto在現有程式指BLE裝置自動選擇，本次不把它當成全新自動AI路由。

用SnpComputeController的sources／volumes／selectedSourceId判定目前USB：偵測到可運算USB pair或removable卷時呈現「USB・手機C」來源狀態，預先載入當前主題set；插入不啟動工作。首次SAF授權、多組pair選擇、debug放可展開來源操作，不佔據整個聊天body。没有USB時原BLE／In App／一般聊天sendUserMessage行為維持；USB存在但未授權、來源不唯一、選擇失效、set不支援／載入中／錯誤時送出禁用或明確攔截，不fallback至其他路徑。USB工作中拔除仍是取消／錯誤，不重送訊息至網路。

USB ready時原composer送出固定捕捉文字／主題／set／來源／debug，呼叫現有runLoci。原聊天歷史仍可見，在訊息流末端顯示本次暫存使用者泡泡與assistant計算卡片（進度／取消／成功或錯誤），不寫ChatController.messages／SharedPreferences，不自動TTS或LLM。每次只保留最新USB工作訊息與结果，下一次送出替換上一組；工作中禁用重送並鎖定主題、來源與debug。結果沿用77位點、模型警示、計時與可複製API JSON；取消／拔除／來源或主題變更／登出使可匯出結果失效，stale guard不變。

範圍內：送出路由與同訊息流呈現、USB狀態／授權、多組選擇、debug及回歸驗證。範圍外：自動API傳輸、聊天基因資料持久化、重寫BLE／C模型／USB provider、新增臨床校準。拒絕只把離線開關預設開啟的替代方案，因為仍會替換訊息流，未滿足本次操作要求。

### 聊天室離線流程與API JSON

追加範圍為同一聊天室的明確「USB離線SNP」模式。一般聊天送出仍沿用既有行為；離線模式的送出按鈕帶入當下文字、健康主題映射的set與已選USB來源，呼叫原生離線工作而非sendUserMessage的網路路徑。插入後呈現來源狀態／掃描與首次SAF授權，不因插入自動運算或送出。多組來源需選擇；沒有資料的主題仍可一般聊天，但離線模式不可執行。busy鎖定主題／模式／debug，取消、拔除、來源／主題變更、登出均使舊job卡片與可複製JSON失效。聊天室卡片是暫存UI資料，不寫入現有聊天歷史持久化，不影響TTS。保留獨立頁為進階工具，不要求聊天室流程導頁。

新增純Dart serializer只轉換C結果，不重算模型。完成後產生可選取／顯式複製的API request JSON，與`ApiService.askLlm`一致：user_id取llmUserId非空值否則threadId；query固定捕捉送出文字；topic使用原有中文映射；SNP_list、snp_list、variants為相同的唯一rsID-GT列表；variant_input_count為位點數、variant_used_count為成功輸出數、no_call_count為未判定位點數、yuguard=null，不捏造生理資料。字串GT保留REF優先、ALT依A/C/G/T順序的固定allele順序（例如REF=T、ALT=C的0/1轉TC），不包含斜線；no-call不放進三個variants列表，但完整locus診斷保留。重複rsID跨不同座標拒絕輸出，不任意取第一筆。酒精完整結果77位點，143是輸入參考筆數，不是輸出位點數。診斷包schemaVersion=2另含job、set、模型、77列、debugTiming（僅啟用時）；API request不混入診斷欄位／URI／序列／read ID。無論debug是否開啟都可產生API JSON，不自動保存／HTTP／LLM呼叫。

### 同位點聯合統計模型

新增獨立`dm-locus-research-v1`，不把已完成`bb-research-v1`的143個獨立posterior相乘、不加總重複REF深度、不挑最大單列posterior。Dirichlet-multinomial為beta-binomial的多分類延伸，使用四類互斥read計數；這是本專案k-mer證據研究模型，不是GATK或品質分數模型。參考方法：https://academic.oup.com/bioinformatics/article/33/15/2322/3071980。

依header的rsID／chrom／position分組；所有同位點query須有相同REF與正規化後相同300bp側翼，若不同則整批INVALID_QUERY，不把不同上下文當同位點。每位點從同一側翼生成A/C/G/T中心查詢（參考asset143筆保持不改），共同稀疏read表取得四等位support。每個read、方向、查詢位置只計一次，背景coverage在四個等位查詢共用；每方向沿用coverage>58才納入支持。正反向支持合併後唯一非零最大support歸入一個鹼基，最大值並列歸ambiguous，皆零歸coverageOnly；每read在位點只貢獻一次，total=sum(A,C,G,T)+ambiguous+coverageOnly，effectiveDepth=sum(A,C,G,T)。保留原100萬候選上限、seek／posting驗證、取消與高頻桶回報，不能使用143列的aggregate重建互斥計數。只逐位點保留read表，read ID不離開C、不輸出logcat；R1/R2仍是不同read而非獨立fragment，相關性為模型限制。

四鹼基排序以REF為allele0，其餘A/C/G/T固定排序；枚舉所有i<=j共10候選（包含ALT/ALT）。dosage d_b取0、0.5、1，均值mu_b=d_b*(1-epsilon)+(1-d_b)*epsilon/3；總和為1，concentration=1/rho-1，alpha_b=mu_b*concentration。略去所有genotype共用多項係數，logLikelihood=lgamma(concentration)-lgamma(n+concentration)+sum_b[lgamma(count_b+alpha_b)-lgamma(alpha_b)]，加log prior後log-sum-exp正規化。預设epsilon=.01、rho=.02、10個均等prior、minDepth=10、minPosterior=.99，calibrated=false；範圍沿用現有epsilon/rho限制、priors正且總和1容差1e-9、n<=100萬。n=0、低深度、最大posterior<門檻、最高log score在1e-12內並列皆no-call，輸出reason；數值／參數非法是錯誤，不fallback。bestGenotype是模型下估計非確認真實GT，診斷保留10候選posterior、最佳posterior及最佳對次佳log score差。沒有BQ不阻擋此count模型，但固定錯誤率不視為校準，需已知GT驗證。

Android run新增明確locus模式，舊query模式契約保持；locus完成事件77列，進度77/77、另標示來源143參考筆數，每列含rsID／chrom／position、四類counts、allele排序、GT indices／actualGenotype、posterior、reason／config／modelVersion。debug按位點重新量測實際I/O、count及joint model，不加總舊143列時間；沿用0.01ms驗證。Flutter捕捉job的query／topic／set／source快照，不用目前聊天室選單重標結果。

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

酒精來源是 `/Volumes/Untitled/MXIC_NCKU_demo_v4/ref_dataset/alcohol.set143.k150.fasta`，原始 SHA-256 為 `0bc77278d47ddcf41f1bbf4ef6f879d47f86c2d06791c0e29c5c0812a72b73f9`。實作時將原始 bytes 內建於 `assets/snp_sets/alcohol.set143.k150.fasta`，在 `pubspec.yaml` 宣告；不採用 gene_annotated 版本，不使用 remoteV3 的另一份資料。實際資料有77個不同位點、143筆等位查詢，內建set以完整header作query id（例如 `rs1229984_4_100239319_T_C`）區分同位點的不同ALT，REF／ALT與序列／順序不變。沿用 `SnpQuery.parseFasta` 並增加明確的 alleleQualifiedIds 選項，舊手動模式的id與重複檢查不變；內建set需恰143個唯一完整query id及77個位點、全部301bp ACGT、中心為 REF 或 ALT且兩者不同，任一失敗整組不可開始。每筆僅做獨立二等位查詢，不合併成多等位聯合GT、不把143列稱為143獨立SNP，UI明示此限制。

asset 載入顯示 loading／ready／error 與 set 名稱、版本、筆數，只有 ready 且 USB來源已選才可執行。選單、進階模式及輸入在 busy 時禁用；載入請求帶 generation，晚到舊載入不可覆蓋新模式。切換 set／模式時清除舊結果與 debug 報告，job 固定捕捉 setId／setLabel／setVersion及143筆 queries，完成頁與 debug 報告標明此次實際運算 set，不能拿目前選單重新標記舊結果。手動模式標明單 SNP 或自訂 FASTA，不冒充內建酒精。

完整驗收路徑為：選酒精→asset驗證143筆→USB唯讀授權／pair選取→C SNP計數→獨立C genotyping→143列結果／no-call及debug階段时间。Widget／controller 測試用 fake platform 驗證傳入的143筆與實際asset相同、完成列數及set版本；native／JNI fixture 仍負責驗證核心計數及模型，不能用fake平台冒充實機USB。Pixel實測记录手機、set版本、USB來源、完成／錯誤、计時、取消與拔除；未知真實GT不當正確性證據，需用人工已知fixture或獨立核對。離線功能不送出 HTTP／LLM 呼叫；本次「整個流程」驗收界線是 LLM 之前，原本AI URL API不變。

## Implementation Contract

- USB結果沿用既有LLM功能驗收：實作下面Reuse existing LLM API for completed USB chat jobs、Job-scoped USB LLM responses and explicit retry。先以fake ApiService/controller/widget失敗測試驗證GeneLLM off無HTTP、on在完整完成後恰一次/v1/ask、77/70/7計數／相同variantlists／快照context與null yuguard、不傳diagnostic／URI／序列。測試GeneLLM on/off在run中變更仍以送出快照為準，重複完成／JSON hide/show不重送、正在等待泡泡及busy、answer沿用_Bubble、不執行BLE／mock／自動TTS／持久化／API debuglog。HTTP錯誤與顯式retry保留C完成結果且不重算；拔除／來源／主題／登出／dispose後late成功與失敗不復活，舊finally不影響新請求。Fake成功不能宣稱實際server回應；執行Flutter全套tests／analyze及ARM64 build，文件記錄需GeneLLM on與URL可達、已送請求不可撤回、安裝另需使用者要求；3.3仍保留真實USB驗收。

- 插入即確認與精簡JSON驗收：先寫失敗tests涵蓋「無USB→插入→不碰主題即一個AlertDialog」、首次已有USB／無set／pending asset／error及刷新去重、busy後處理、路由返回與拔除清理。成功77位點結果只見有界API JSON，不見逐位點／posterior／debug全文；上方切換隱藏使目前與下次JSON正文和語意節點消失、重開頁沿用boolean但不恢復結果、重新显示不增加run／HTTP／clipboard。明確查看診斷仍有分段時間、debug off無報告、失效關閉診斷。以`test/snp_chat_panel_test.dart`及controller／必要Android tests驗證，執行全套Flutter test／analyze、Android SNP／USB tests與ARM64 build；Pixel真實插入時序、SAF／USB效能另記錄，不以fake或建置當已完成3.3。
- USB插入確認最新驗收：`test/snp_chat_panel_test.dart`及controller tests先失敗驗證插入／首次已掛載僅一個可關閉AlertDialog、refresh與授權返回不重彈、關閉不確認／不run／不HTTP、圖示可重開、拔除／dispose／logout清理及late不復活；確認來源後才能原composer送出，仍143參考→77位點／JSON，主題set與busy guard不變。原設定箭頭／debug仍在上方，確認視窗不取代聊天室。Android `SnpContractsTest.kt`與相關tests驗證root initial URI、primary拒絕、保存唯讀權限、目前選擇／同UUID有效記錄／唯一pair／多組未選恢復順序、被撤權與移除來源不恢復、scanner範圍與資源上限不放寬。首次根目錄仍需系統確認，私有儲存只新增來源metadata，禁止保存基因結果；fake／fixture／真實PixelUSB分開記錄。
- USB icon最新验收：`test/snp_chat_panel_test.dart`先定義無USB無icon、插入顯示icon、hover與long-press顯示選定label且不含sourceId／URI、展開上方下拉設定不啟動工作、多組未選不猜來源、拔除清除label／icon；保留原聊天泡泡，只有送出才計算77位點，busy禁用來源／debug、取消與stale guard不變。不得把偵測icon等同已授權就緒。
- 2026-10-01優先介面驗收：移除USB離線模式開關，不以SnpChatControls取代聊天歷史；USB來源狀態與送出路由依上述「USB運算來源與原聊天訊息流」。`test/snp_chat_panel_test.dart`須驗證無需切模式、舊泡泡可見、輸入問題→C收到143參考→77/77→原訊息流有暫存文字／結果／JSON；禁止HTTP／持久化／TTS。另驗證未授權／多來源／無set／載入錯誤禁用、busy鎖定、取消與拔除不fallback、stale不復活、沒有USB時原sendUserMessage。模型與serializer既有tests維持通過。
- 追加優先契約：聊天室使用上述聯合locus模式與API JSON。已完成獨立頁的143列二等位行為保留為進階／legacy模式；以下query契約與既有驗收不代表新locus功能已完成。API傳輸、自動持久化、BQ推造、臨床校準、舊USB匯入、TTS不在追加範圍。
- 追加驗收：C共同fixture核對四類去重、跨ALT/方向不增深度、ALT/ALT與無支持的鹼基、非法上下文；模型與独立高精度參考比對10候選posterior，驗證對稱／參數／no-call。Flutter fake聊天室測試選酒精→文字送出→77/77→唯一位點JSON、debug on/off結果相同、清空／取消／拔除stale guard，禁止HTTP；API payload tests精確核對askLlm欄位、REF=T/ALT=C轉TC、no-call排除及重複rsID拒絕。實機與fixture分開紀錄。

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

聊天室／locus程式修改前，再將目前已安裝可用的set／debug版及限定相關規格Git備份到遠端codex/分支，核對SHA，不混入其他功能。新增模式而非覆寫legacy模型，回退可重建備份APK並install -r，不清除手機資料。

先備份現有版本到 Git，再新增獨立函式庫與頁面；現有功能不遷移。若需要回退，使用備份 commit 重建 APK，不清除 USB 或使用者資料。

debug 實作前，另將目前已完成的 SNP 版本建立限定本功能檔案的 Git 備份 commit 與遠端 codex/ 備份分支，驗證遠端 commit；不夾帶其他功能的變更。

此備份也必須在 SNP set UI／asset 程式修改前完成。新版建置後不自動標記3.3為完成；先記錄安裝成功，再獨立記錄實際USB流程驗收。

## Open Questions

無阻擋實作的設計選項。模型校準及 Pixel 真實 USB 效能屬驗收中需量測事項，不冒充已完成。
