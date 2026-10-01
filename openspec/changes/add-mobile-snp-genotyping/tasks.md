## 1. 獨立原生核心

- [x] 1.1 [P] 以失敗測試先定義並實作 Bounded native SNP counting／稀疏 C 計數：固定寬度解碼、跨4GiB偏移、posting 邊界、read去重、方向合併、模糊分類、高頻桶回報及100萬候選上限；在 `test/native/snp_engine_test.c` 驗證人工fixture、取消、錯誤及 total 分解，禁止漏計或超限截斷成功。
- [x] 1.2 [P] 以失敗測試先定義並實作 Independent beta-binomial genotyping／Beta-binomial 判定：獨立 `genotype_model` 計算log likelihood、prior與正規化posterior，驗證參數、版本與no-call；在 `test/native/genotype_model_test.c` 驗證REF=4/ALT=4的深度8 no-call、零深度、对稱性、總和、極端計數及非法參數。

## 2. Android 與 USB 整合

- [x] 2.1 實作 Direct USB source access／USB 直接讀取：沿用掛載與SAF唯讀授權、不依賴匯入、列出多組同目錄pair供選擇，拒絕手機primary儲存，驗證IDX大小、IDs對齊、seek與權限；以Android測試驗證來源拒絕、資料損毀、多組來源與許可取消，保留既有USB匯入行為。
- [x] 2.2 整合 Flutter 背景整合 的 JNI與SnpComputePlugin契約，註冊geneedge/snp_compute及events、工作ID／revision、單job限制、冪等取消、detach／拔除取消、所有FD關閉並更新獨立CMake target；以Android測試及ARM64 APK build驗證正常與失敗生命週期，確認不修改AI與TTS行為。

## 3. Flutter 操作與驗證

- [x] 3.1 實作 Independent Flutter compute workflow／Flutter 背景整合：先寫Dart controller與widget失敗測試，再新增頁面與drawer入口，支援USB來源、301bp單SNP與最多3000筆FASTA驗證、進度／取消／錯誤、posterior／GT／模型配置與研究警示；以 `test/snp_compute_test.dart` 及 `test/snp_compute_page_test.dart` 驗證深度8 no-call、stale事件、非Android與輸入整批拒絕。
- [x] 3.2 新增 `docs/mobile-snp-genotyping.md` 說明USB直接讀取、模型假設、與demo差異、校準需求及操作步驟；執行native tests、flutter test、flutter analyze、Android單元測試與ARM64 build並記錄既有失敗，不把未執行的實機驗收標成成功。
- [ ] 3.3 以Pixel及真實USB pair完成直接讀取超4GiB位置、與人工fixture桌面計數對照、記憶體／耗時量測、取消與拔除測試；記錄手機、來源與結果，無USB或Pixel可用時保持此項未完成。

## 4. Debug 結果與分段計時

- [x] 4.1 在任何 debug 或 SNP set UI／asset 程式修改前，將目前 SNP 版本及本次規格以限定檔案的 Git commit 備份到遠端 codex/ 分支；以 git status、commit 檔案清單及 git ls-remote 驗證沒有夾帶其他功能，遠端 SHA 與本地一致，記錄可回復位置。
- [x] 4.2 以失敗測試先實作 Opt-in debug results and stage timing／Debug 結果與分段計時 的 C／JNI 量測：實際 fstat／pread I/O 累計、扣除 I/O 的 countMs、獨立 genotypeMs 與 native overhead／total；debug 關閉略過逐讀取計時。依賴4.1，以可控制時鐘／合成資料驗證 12ms query含7ms I/O→5ms計數，以及 `scripts/test_snp_native.sh` 驗證真實 fixture 非負時間、分解一致與 on/off 計數及 GT 相同。
- [x] 4.3 接續4.2更新 SnpComputePlugin 的 debugEnabled 快照、setupIoMs、queryIoMs／countMs／genotypeMs 加總、batch overheadMs／totalMs 與中斷 elapsedMs；GeneEdgeSnp logcat 只在啟用時列印有界且 escaped 的結果／時間，不含序列、read ID 或 URI。以 Android 單元測試驗證22ms人工分解、預設关闭、日誌3000 UTF-8 bytes上限、隱私欄位、失敗／取消摘要及 stale guard。
- [x] 4.4 接續4.3以 Flutter controller／widget 失敗測試新增預設關閉、busy不可切換的 debug 開關，驗證run快照、有限非負時間與0.01ms分解容差；顯示逐 SNP 及整體階段、schemaVersion=1可選取報告與顯式複製按钮／敏感資料提示。以 `test/snp_compute_test.dart`、`test/snp_compute_page_test.dart` 驗證顯示／剪貼簿、不輸出原始資料、非法時間拒絕、取消及來源變更清空報告，舊無debug呼叫仍可運作。
- [x] 4.5 接續4.4更新 `docs/mobile-snp-genotyping.md` 的 debug 測試操作、elapsed邊界、provider／cache影響及量測開銷；執行 native／Flutter／Android 測試、flutter analyze與ARM64 APK build，記錄結果與既有失敗。Pixel無法連線時保留3.3未完成；可連線時在3.3實測debug開關、每階段顯示／複製、logcat及取消／拔除，不能冒充已安裝或實測。

## 5. SNP set 選單與整個離線流程

- [x] 5.1 依賴4.1備份，先以 `test/snp_sets_test.dart` 定義 Topic SNP set selection and bundled alcohol panel／SNP set 選單與內建酒精資料 契約，將指定USB原始酒精參考FASTA內建於 `assets/snp_sets/alcohol.set143.k150.fasta` 並宣告pubspec asset；實作catalog、hash與143筆完整驗證、原始REF／ALT及locus id保留，其他主題標示不可用。測試驗證原始SHA-256、143筆301bp、rs1229984 locus、壞資料整組拒絕與無個人combined asset。
- [x] 5.2 接續5.1及4.4，以widget失敗測試將SNP頁主要輸入改為主題set選單並預選酒精，顯示loading／ready／error、筆數與版本；保留進階單SNP／外部FASTA。controller固定捕捉set job快照，切換清空結果與debug報告、busy禁用切換、stale載入不覆蓋新模式；在 `test/snp_compute_page_test.dart`、`test/snp_compute_test.dart` 驗證傳入完整143筆與asset一致、其他主題不可執行及缺USB／載入錯誤不可開始。
- [x] 5.3 接續5.2實作 End-to-end offline alcohol workflow verification 的自動化驗收及文件：fake platform驗證選酒精→143筆查詢→143/143進度→結果／no-call與debug分段時間及set版本，並驗證沒有自動HTTP／LLM呼叫；與native／JNI fixture結果分開記錄。執行全套Flutter測試、analyze及ARM64 build，`docs/mobile-snp-genotyping.md` 提供Pixel USB整流程、取消／拔除、結果對照測試步驟；物理USB驗收仍由3.3記錄，安裝成功不等於正確性驗證。

## 6. 聊天室與每位點聯合判定

- [x] 6.1 在本組程式修改前，將目前可用set／debug版及相關規格限定檔案Git備份到遠端codex/分支；核對commit檔案清單與git ls-remote SHA並記錄回復位置，不夾帶其他功能。
- [x] 6.2 依賴6.1，以失敗測試實作 Joint locus evidence and statistical genotyping／同位點聯合統計模型 的C共同四等位read表；驗證REF／側翼一致、四類互斥計數、跨ALT與方向去重、ambiguous／coverageOnly、candidate上限、取消、I/O錯誤及64bit位置，於test/native/snp_locus_test.c核對已知fixture，不用舊aggregate計數替代。
- [x] 6.3 接續6.2，以test/native/locus_genotype_model_test.c失敗測試實作獨立C dm-locus-research-v1：10候選Dirichlet-multinomial、均等prior、posterior與最大後驗／no-call；與獨立數值參考核對，驗證100C/100G選C/G、低深度、並列、鹼基置換對稱、極端計數與非法參數，保留legacy beta-binomial tests。
- [x] 6.4 接續6.3，新增JNI／Android明確locus run模式及77列契約、原生四類counts／posterior／實際GT／模型版本與逐位點debug；保留舊run格式與取消／FD所有權。以真正JNI fixture、Android契約tests及debug on/off對照驗證77位點事件、有限時間分解與stale guard。
- [x] 6.5 接續6.4，實作snp_sets分組及controller的query／topic／set／source job快照、locus完整性驗證、77/77、debug與失效清除；以test/snp_compute_test.dart、test/snp_locus_compute_test.dart及test/snp_sets_test.dart驗證143原始記錄→77同側翼位點、REF錯誤拒絕、取消／來源變更／晚到事件不可還原舊結果。
- [x] 6.6 接續6.5，以test/snp_api_payload_test.dart失敗測試實作 Unique-locus API JSON export／聊天室離線流程與API JSON 的純serializer：askLlm精確欄位與三份相同variants、GT鹼基轉換、每位點唯一、重複rsID跨座標拒絕、77/70/7計數、diagnostic schemaVersion=2，不含序列／read ID／URI，debug off仍可產生但無網路／自動保存。
- [x] 6.7 接續6.6，以聊天室widget失敗測試實作 Chat-integrated offline USB computation：原有主題映射set、明確USB離線模式、輸入文字送出C、來源／權限、載入／錯誤、進度／取消、暫存結果／JSON與分段計時卡片／顯式複製。驗證同頁完成77/77、一般聊天仍原路徑、busy鎖定、未提供set禁用、拔除／登出清空、禁止HTTP／持久化／自動TTS，不要求導頁。
- [x] 6.8 接續6.7，更新docs/mobile-snp-genotyping.md的聊天室操作、JSON範例、joint模型與legacy區分、校準限制及Pixel測試；執行native／JNI、Flutter全套test／analyze、Android相關tests、ARM64 build，分開紀錄fixture與真實USB驗收。未執行實機測試不得勾選3.3。

## 7. USB來源與原聊天室訊息流修正

- [x] 7.1 在介面程式修改前，將已安裝的聊天室joint版與本次相關規格限定檔案備份至遠端codex/分支；以commit清單及git ls-remote核對SHA，排除其他功能與個人資料，於文件記錄回復位置。
- [x] 7.2 依賴7.1，以test/snp_chat_panel_test.dart失敗測試實作 USB-source chat message flow／USB運算來源與原聊天訊息流 的送出路由：移除USB離線開關，從sources／volumes判斷USB、主題預載set、ready時送出runLoci，未授權／多來源未選／無set／載入中或錯誤明示禁用且無BLE／Local JSON／HTTP fallback；驗證busy與拔除guard，無USB時原聊天路徑不變。
- [x] 7.3 接續7.2，以聊天室widget失敗測試將USB狀態／授權／來源與debug改為可展開操作，保留原聊天泡泡與composer，在同一訊息流末端顯示最新暫存使用者泡泡及計算進度／取消／結果／API JSON卡片；驗證143參考→77/77、舊泡泡可見、顯式複製、debug分段時間、取消／拔除／登出清空匯出與stale抑制、禁止持久化／TTS／網路，不重寫C模型或serializer。
- [x] 7.4 接續7.3更新docs/mobile-snp-genotyping.md的USB送出流程與已安裝／實測狀態；執行全套Flutter test／analyze、native／JNI回歸、ARM64 build，記錄結果。提供Pixel測試步驟；僅在使用者要求安裝時執行install -r，無真實USB验收仍保持3.3未完成。

## 8. USB偵測圖示與資料夾提示

- [x] 8.1 在icon介面修改前，將目前已安裝的原訊息流版及相關追加規格限定檔案備份到遠端codex/分支，核對commit檔案清單及git ls-remote SHA；排除其他功能／個人USB資料，於文件記錄回復點。
- [x] 8.2 依賴8.1，以test/snp_chat_panel_test.dart失敗測試實作 USB detection icon and folder tooltip／USB偵測圖示與資料夾提示：既有上方下拉設定標頭的偵測icon、ready／待設定文字、hover與long-press Tooltip對應sources.label、不洩漏sourceId／URI；點擊icon或設定按鈕展開同一下拉區的授權／來源／debug內容，限制可捲動高度且鍵盤開啟不overflow，不另設AppBar／bottom sheet入口，移除常駐訊息流設定卡片。驗證多組未選不猜、拔除清除icon／tooltip、busy禁用設定、舊泡泡仍在且插入／hover／展開皆不run，送出才C計算77位點，取消與stale無回退HTTP。
- [x] 8.3 接續8.2更新docs/mobile-snp-genotyping.md的icon／hover／手機長按／點擊設定操作；執行Flutter全套test／analyze與ARM64 build並記錄結果及未安裝狀態。只在使用者要求時install -r；真實USB結果與效能驗收3.3仍須獨立執行。

## 9. USB插入確認與根目錄授權恢復

- [x] 9.1 在本組程式修改前，將已安裝USB圖示版的相關五個dirty檔與本次四份規格限定Git備份到遠端codex/分支，核對commit檔案清單與git ls-remote SHA，排除其他功能／USB個人資料，記錄可回復SHA。
- [x] 9.2 依賴9.1，以Android失敗測試實作 USB root authorization and source restoration／USB插入確認與根目錄授權恢復 的原生部分：mounted removable UUID根目錄initial URI、首次顯式系統授權／保存唯讀grant、舊子目錄範圍明示、discover保留當前／恢復同卷有效metadata／唯一pair自動選／多组未選不猜；只保存來源metadata，撤權／來源消失／primary拒絕，掃描深度16／10000項及取消保持。於SnpContractsTest.kt與相關Android tests驗證恢復策略、root定位與失效，保留舊USB回歸。
- [x] 9.3 接續9.2，以Flutter controller／test/snp_chat_panel_test.dart失敗測試實作 Dismissible USB insertion confirmation：每次掛載UUID或首次已掛載自動一個可關閉AlertDialog，返回／點外部／取消不確認、不反覆彈出、不run／HTTP，USB圖示可重開、設定箭頭仍展開上方區；已有grant沿用、未授權按鈕開系統picker並展示實際範圍，多USB／多來源明確選擇，僅確認有效來源後才能聊天送出77位點。驗證refresh／授權返回去重、鍵盤無overflow、busy／logout／拔除／dispose及late清理，原泡泡、debug、JSON與no-fallback不變。
- [x] 9.4 接續9.3更新docs/mobile-snp-genotyping.md的確認／關閉／重開、根目錄與子目錄限制、授權與來源恢復操作、備份SHA；執行Flutter全套tests／analyze、Android SNP／USB tests及ARM64 build，記錄fake與實機狀態，不自動安裝。只有使用者要求時install -r；真實USB3.3未驗證仍未完成。

## 10. 插入即確認與精簡JSON

- [ ] 10.1 在本組程式修改前，將目前已安裝USB確認版的相關dirty程式／tests／文件及本次四份規格限定Git備份到遠端codex/分支；核對git status、commit檔案清單及git ls-remote SHA，記錄回復位置，排除其他功能與個人USB資料。
- [ ] 10.2 依賴10.1，以失敗測試實作 Topic-independent USB insertion prompting／插入即確認與精簡JSON 的掛載提示部分：檢查並修正controller通知、原生掛載／discover與post-frame／路由時序，使前景idle插入在未選主題、無set、載入中或錯誤時皆自動顯示一次確認，不等待主題tap、不自選酒精。以test/snp_chat_panel_test.dart及controller／必要Android tests驗證首次已有USB、refresh去重、busy後及路由返回處理、拔除與late清理、根目錄授權行為不變、不run／HTTP，來源掃描尚未完成不可冒充ready。
- [ ] 10.3 接續10.2，以失敗測試實作 Compact API JSON presentation and visibility preference 及 Explicit bounded chat diagnostics：聊天室成功卡片只有有界可捲動API JSON、簡短完成與顯式複製，移除逐位點／posterior／debug全文；上方「顯示 API JSON」預設true、只保存boolean、載入前不展示正文且late偏好不覆蓋新切換，關閉使現在及後續正文／語意節點消失，重開頁沿用偏好不恢復結果、重新顯示不重算。上方顯式診斷視窗保留debug／分段計時、研究警示與複製，失效／登出／dispose關閉。以widget／controller tests驗證77位點JSON契約未改、debug off無報告、隱藏與busy只影響呈現、無HTTP／TTS／基因結果保存／自動clipboard。
- [ ] 10.4 接續10.3更新docs/mobile-snp-genotyping.md的插入免主題操作、精簡JSON／隱藏偏好、主動查看診斷、備份SHA及實機狀態；執行全套Flutter tests／analyze、Android SNP／USB tests及ARM64 build，區分fake／fixture與Pixel真實掛載驗收。只在使用者要求時安裝，3.3真實USB計數／效能未驗證保持未完成。
