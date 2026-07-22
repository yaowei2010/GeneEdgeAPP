## 1. 隔離入口與 Flutter contract

- [x] 1.1 [P] 依「Keep the PoC behind compile-time and runtime flags」建立預設關閉的 `bluemagpiePoc` Gradle/CMake/Flutter flags，使 source 或模型不存在時正式路徑仍可建置；以 flag-off `flutter analyze`、`flutter test` 與 `flutter build apk --debug --target-platform android-arm64` 驗證。
- [x] 1.2 [P] 依「Reuse Flutter channels through a dedicated plugin」以 TDD 建立 `BlueMagpieTts` typed API、MethodChannel/EventChannel names、state/result/error models與 fake channel，先讓 `test/bluemagpie_tts_test.dart` 失敗再通過，驗證 stable serialization與idempotent cancel/release。
- [x] 1.3 完成「Isolated Android PoC entry」，新增 developer-only診斷頁顯示probe、model、lifecycle、metrics並只在Android ARM64 debug + flag enabled時可達；以widget tests驗證支援與不支援平台的navigation差異。
- [x] 1.4 將 flag-on debug PoC 隔離為 `com.example.geneapp.bluemagpie` 並使用獨立顯示名稱與 app-specific model directory，避免真機測試覆蓋既有 `com.example.geneapp`；以 APK application ID 與雙套件共存檢查驗證。

## 2. 模型安全與 Android worker

- [x] 2.1 [P] 依「Install models outside Git with a verified manifest」完成「App-private model validation」，固定upstream revision、檔名、byte size、SHA-256、license/provenance並拒絕internal no-backup model directory外的canonical path；以model validation matrix unit tests及Git/APK檔案清單檢查驗證。Android 16 真機確認不得直接由 adb 建立 external app-specific model directory，故改用 App 自建 no-backup storage 與 debug `run-as` sideload。
- [x] 2.2 [P] 建立獨立 `BlueMagpieTtsPlugin` worker executor與events，使所有model work離開main thread且plugin detach會release；以Android unit tests或instrumented fake native bridge驗證main-thread callback、duplicate call與detach cleanup。

## 3. Codec-enabled native runtime

- [x] 3.1 依「Pin codec source without embedding React Native」將codec branch固定在commit `7d5cf82cf33883bc80ec845905f5d85c5565d132`，只納入C++ runtime且不引入npm/JSI/React Native；以submodule status、license inventory及flag-on CMake configure驗證revision與dependency boundary。
- [x] 3.2 依「Separate native libraries and load BlueMagpie lazily」完成「Runtime provenance report」，建立hidden-symbol `libgeneedge_bluemagpie.so`與JNI probe，使App啟動不載入模型且runtime缺失回傳`runtime_missing`；以`readelf`/APK library listing與probe instrumented test驗證。
- [ ] 3.3 完成「Explicit native lifecycle」，實作single-context initialize/release、worker cancellation checks、backend與RSS量測，duplicate initialization不得二次配置；以native lifecycle tests及真機重複initialize/release 20次驗證。
- [ ] 3.4 依「Generate complete WAV before adding streaming」完成「Offline WAV synthesis」，將固定中文句與最多200 Unicode scalar values合成private-cache mono 48 kHz PCM WAV並驗證header/sample count/metrics；以native smoke test解析WAV且在真機播放驗證。
- [ ] 3.5 完成「Cancellation and cleanup」，使active request停止接收frames、partial WAV刪除、頁面dispose後context釋放且可再次合成；以cancel-before-audio、cancel-during-decode與dispose instrumented tests驗證。

## 4. 量測、錯誤隔離與fallback

- [ ] 4.1 [P] 依「Measure every native operation with a stable result schema」完成「Structured failure isolation」，統一所有error codes與safe metadata，metrics JSON不得包含任意path、native exception或健康文字；以table-driven Dart/Kotlin/native error mapping與redaction tests驗證。
- [ ] 4.2 [P] 依「Fail closed and allow one CPU fallback」使manifest/ABI/revision不符禁止初始化、Vulkan失敗只fallback CPU一次、allocation/decode錯誤不終止process；以fake backend failure tests與真機invalid-model test驗證。

## 5. 離線與回歸結論

- [x] 5.1 完成「Offline and regression verification」自動部分，執行flag-off與flag-on-no-model兩套CI命令，確認現有login/chat/BLE/ASR/LLM tests無回歸且no-model page結構化失敗；保存command與結果於`docs/bluemagpie-android-poc.md`。
- [ ] 5.2 完成「Offline and regression verification」真機部分，以飛航模式合成固定中文句並執行20次soak，記錄device/SDK/RAM/SoC/backend/revisions/load/first-audio/total/peak-RSS/output-duration/crash/ANR結果；只有20次完成且無partial WAV殘留才把PoC判定為可進入聊天整合評估。
