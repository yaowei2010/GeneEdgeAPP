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

- [ ] 4.1 在任何 debug 或 SNP set UI／asset 程式修改前，將目前 SNP 版本及本次規格以限定檔案的 Git commit 備份到遠端 codex/ 分支；以 git status、commit 檔案清單及 git ls-remote 驗證沒有夾帶其他功能，遠端 SHA 與本地一致，記錄可回復位置。
- [ ] 4.2 以失敗測試先實作 Opt-in debug results and stage timing／Debug 結果與分段計時 的 C／JNI 量測：實際 fstat／pread I/O 累計、扣除 I/O 的 countMs、獨立 genotypeMs 與 native overhead／total；debug 關閉略過逐讀取計時。依賴4.1，以可控制時鐘／合成資料驗證 12ms query含7ms I/O→5ms計數，以及 `scripts/test_snp_native.sh` 驗證真實 fixture 非負時間、分解一致與 on/off 計數及 GT 相同。
- [ ] 4.3 接續4.2更新 SnpComputePlugin 的 debugEnabled 快照、setupIoMs、queryIoMs／countMs／genotypeMs 加總、batch overheadMs／totalMs 與中斷 elapsedMs；GeneEdgeSnp logcat 只在啟用時列印有界且 escaped 的結果／時間，不含序列、read ID 或 URI。以 Android 單元測試驗證22ms人工分解、預設关闭、日誌3000 UTF-8 bytes上限、隱私欄位、失敗／取消摘要及 stale guard。
- [ ] 4.4 接續4.3以 Flutter controller／widget 失敗測試新增預設關閉、busy不可切換的 debug 開關，驗證run快照、有限非負時間與0.01ms分解容差；顯示逐 SNP 及整體階段、schemaVersion=1可選取報告與顯式複製按钮／敏感資料提示。以 `test/snp_compute_test.dart`、`test/snp_compute_page_test.dart` 驗證顯示／剪貼簿、不輸出原始資料、非法時間拒絕、取消及來源變更清空報告，舊無debug呼叫仍可運作。
- [ ] 4.5 接續4.4更新 `docs/mobile-snp-genotyping.md` 的 debug 測試操作、elapsed邊界、provider／cache影響及量測開銷；執行 native／Flutter／Android 測試、flutter analyze與ARM64 APK build，記錄結果與既有失敗。Pixel無法連線時保留3.3未完成；可連線時在3.3實測debug開關、每階段顯示／複製、logcat及取消／拔除，不能冒充已安裝或實測。

## 5. SNP set 選單與整個離線流程

- [ ] 5.1 依賴4.1備份，先以 `test/snp_sets_test.dart` 定義 Topic SNP set selection and bundled alcohol panel／SNP set 選單與內建酒精資料 契約，將指定USB原始酒精參考FASTA內建於 `assets/snp_sets/alcohol.set143.k150.fasta` 並宣告pubspec asset；實作catalog、hash與143筆完整驗證、原始REF／ALT及locus id保留，其他主題標示不可用。測試驗證原始SHA-256、143筆301bp、rs1229984 locus、壞資料整組拒絕與無個人combined asset。
- [ ] 5.2 接續5.1及4.4，以widget失敗測試將SNP頁主要輸入改為主題set選單並預選酒精，顯示loading／ready／error、筆數與版本；保留進階單SNP／外部FASTA。controller固定捕捉set job快照，切換清空結果與debug報告、busy禁用切換、stale載入不覆蓋新模式；在 `test/snp_compute_page_test.dart`、`test/snp_compute_test.dart` 驗證傳入完整143筆與asset一致、其他主題不可執行及缺USB／載入錯誤不可開始。
- [ ] 5.3 接續5.2實作 End-to-end offline alcohol workflow verification 的自動化驗收及文件：fake platform驗證選酒精→143筆查詢→143/143進度→結果／no-call與debug分段時間及set版本，並驗證沒有自動HTTP／LLM呼叫；與native／JNI fixture結果分開記錄。執行全套Flutter測試、analyze及ARM64 build，`docs/mobile-snp-genotyping.md` 提供Pixel USB整流程、取消／拔除、結果對照測試步驟；物理USB驗收仍由3.3記錄，安裝成功不等於正確性驗證。
