## Context

GeneEdge 是 Flutter App，Android 目前只建置 `arm64-v8a`，最低 API 28，並已有 `MethodChannel`、JNI、CMake、whisper.cpp/ggml 與 Vulkan 的離線 ASR 原型。BlueMagpie 的公開手機路徑不是官方穩定 TTS API：一般 `llama.rn` 以 React Native/JSI 為主，TTS 實作位於 codec branch；研究時確認 commit `7d5cf82cf33883bc80ec845905f5d85c5565d132` 已內含 `cpp/codec`、Barbet 與 BlueMagpie AudioVAE 相關程式，因此 Flutter 不需要嵌入 React Native runtime。

PoC 的目標是取得可否產品化的實測證據，不是宣告所有 Android 手機已受支援。權重至少約 2.4 GB，推論記憶體與延遲未知；此外 BlueMagpie 聲學架構沿用 OpenBMB/VoxCPM，來源與授權必須保留在診斷文件中。

## Goals / Non-Goals

**Goals:**

- 在 Android ARM64 debug build 中驗證 codec-enabled C++ runtime 能否載入 BlueMagpie Q4 Barbet 與 AudioVAE GGUF。
- 從 Flutter 啟動、取消與釋放離線合成，產生可播放的 48 kHz WAV。
- 量測模型驗證、載入、首音、總生成時間、輸出長度與 process memory。
- runtime/source/model 缺失時保持正式 App 可編譯、可啟動且不 crash。
- 固定 source revision、model revision、SHA-256 與測試裝置資訊，使結果可重現。

**Non-Goals:**

- iOS、x86、32-bit Android 或所有 Android 裝置的正式支援承諾。
- 將 React Native 或 JavaScript engine 嵌入 Flutter。
- 把 GGUF 權重提交至 Git、APK 或 AAB。
- 第一階段串流播放、voice cloning、自動模型下載、背景合成或正式聊天預設啟用。
- 更換既有 LLM API、中文語音輸入或 BLE 流程。

## Decisions

### Keep the PoC behind compile-time and runtime flags

使用 Gradle property `bluemagpiePoc=true` 控制 native source 與 developer entry，預設為 false；Flutter 再以 debug mode 與 Android ARM64 capability 控制入口可見性。flag 關閉時不要求 runtime source、模型或額外 native library，確保 main 可 fast-forward 合併且正式路徑不受影響。

### Reuse Flutter channels through a dedicated plugin

新增獨立 `BlueMagpieTtsPlugin`，使用 MethodChannel `geneedge/bluemagpie_tts` 執行命令，EventChannel `geneedge/bluemagpie_tts/events` 回報狀態。它不繼續擴張現有 `MainActivity` ASR handler，避免 TTS lifecycle 與錄音責任混合。Flutter 端以可注入的 `BlueMagpieTts` class 包裝 channel，tests 使用 fake platform interface。

### Pin codec source without embedding React Native

將 `mybigday/llama.rn` codec branch 以 Git submodule 固定到 commit `7d5cf82cf33883bc80ec845905f5d85c5565d132`，只編譯 `cpp` 中所需 llama/Barbet/codec code，不引入 npm、JSI 或 React Native runtime。若該 commit 無法以 Android NDK 獨立建置，PoC 回報 `runtime_missing`，不得以未固定的其他 fork 靜默替代。

### Separate native libraries and load BlueMagpie lazily

現有 whisper/ggml 保持在 `libgeneedge_whisper.so`；BlueMagpie 使用 `libgeneedge_bluemagpie.so`，各自固定依賴 revision並隱藏 symbols，避免兩套 ggml ABI 與 CMake cache 互相污染。只有使用者開啟 PoC 且模型驗證通過後才載入 BlueMagpie library/context；App 啟動不得配置 TTS model memory。

### Install models outside Git with a verified manifest

模型存於 `getExternalFilesDir(null)/models/bluemagpie`。repository 只保存 manifest，內容含 model ID、upstream revision、檔名、byte size、SHA-256、license URL 與 provenance。PoC 僅接受 canonical path 位於該 private directory 且完整符合 manifest 的檔案。第一階段由 adb 或 Android Studio Device Explorer 安裝，避免把下載管理與 runtime 可行性混成同一風險。

### Generate complete WAV before adding streaming

第一階段將最多 200 個 Unicode scalar values 合成為 private cache 中的完整 mono 48 kHz PCM WAV，再由 Android/Flutter 播放。這使輸出 header、sample count、duration 與取消後清理可直接驗證。只有完整 WAV PoC 達到驗收門檻後，才另提串流設計。

### Measure every native operation with a stable result schema

probe、initialize 與 synthesize 均回傳 monotonic elapsed time；native 讀取 `/proc/self/status` 的 `VmRSS`/`VmHWM`，Android 層補上 `ActivityManager.MemoryInfo`。量測結果與裝置 ABI、SDK、backend、runtime/model revisions 一起顯示並可複製為 JSON，但不得包含任意 filesystem path 或使用者健康內容。

### Fail closed and allow one CPU fallback

模型驗證、runtime ABI 或 revision 不符時禁止初始化。Vulkan 初始化失敗時同一次 initialize 最多自動重試一次 CPU；記憶體不足、decode failure 與 cancellation 均回傳穩定 error code。任何錯誤都不得終止 process，且 partial WAV 必須刪除。

## Implementation Contract

**Observable behavior:** 在啟用 flag 的 Android ARM64 debug build，開發者可進入獨立頁面查看 runtime/model 狀態，載入模型，將固定中文 smoke sentence 合成為 WAV、播放、停止並查看 JSON metrics。flag 關閉、平台不支援、runtime 未編入或模型缺失時，既有 App 可正常使用且不載入模型。

**Flutter interface:**

- `BlueMagpieTts.probe()` → runtime provenance/capability map。
- `BlueMagpieTts.validateModels()` → 每個模型的 validation state 與總 free-space result。
- `BlueMagpieTts.initialize({backend})` → state、backend、elapsedMs、rssBeforeBytes、rssAfterBytes。
- `BlueMagpieTts.synthesize({requestId, text})` → private WAV token、sampleRate、samples、durationMs、firstAudioMs、elapsedMs、peakRssBytes。
- `BlueMagpieTts.cancel(requestId)` 與 `release()` 必須 idempotent。
- EventChannel events 固定含 `requestId`, `state`, `progress`, `timestampMs`, `errorCode`；未知欄位可忽略。

**Native interface:** `libgeneedge_bluemagpie.so` 提供 JNI probe/init/synthesize/cancel/release。Kotlin plugin 負責 worker executor、state serialization、private paths 與 main-thread callback；C++ 負責 runtime contexts、model execution、cancellation checks、PCM/WAV 與 native metrics。

**Failure contract:** 使用 `runtime_missing`, `unsupported_abi`, `model_missing`, `model_path_rejected`, `model_size_mismatch`, `model_checksum_mismatch`, `insufficient_space`, `insufficient_memory`, `backend_unavailable`, `invalid_text`, `decode_failed`, `cancelled`, `io_failed`, `internal_error`。Flutter 顯示安全訊息與 code；完整 native exception 只允許 debug log，不得顯示任意路徑或 memory content。

**Acceptance criteria:**

- flag disabled 時 `flutter analyze`、`flutter test` 與 Android ARM64 debug build 不需要 BlueMagpie source/weights且全部通過。
- fake-channel tests 覆蓋 state transitions、invalid input、duplicate init、cancel、release 與 stable error mapping。
- flag enabled 且無 runtime/模型時，頁面回報結構化 unavailable 狀態且不 crash。
- runtime/model 安裝後，在飛航模式對固定句「今天天氣真好，我們一起去散步吧。」產生非空 mono 48 kHz WAV。
- 真機紀錄 model revisions、device、SDK、RAM、backend、load/first-audio/total latency、peak RSS、output duration 與 20 次連續結果。
- 連續 20 次無 native crash、ANR、殘留 partial WAV 或不可恢復 state，才能評估接入聊天流程。

**Scope boundaries:** 本 change 僅涵蓋 Android ARM64 debug PoC、手動模型安裝、完整 WAV 與量測。正式聊天整合、自動下載、串流、iOS、發布設定及 fallback 系統 TTS 不在範圍內。

## Risks / Trade-offs

- [Codec branch 未主線化且 README 仍稱 TTS unsupported] → 固定 commit、隔離 submodule/feature flag，先以 compile probe 驗證，不把它視為穩定 dependency。
- [模型至少約 2.4 GB且 runtime memory 未知] → 外部安裝、lazy load、記憶體前後量測與 8 GB RAM 級裝置優先測試。
- [兩套不同 ggml revision 可能 symbol/ABI 衝突] → 使用獨立 shared libraries、hidden visibility 與各自 CMake scope。
- [Vulkan driver 差異造成 crash或錯誤輸出] → capability probe、一次 CPU fallback，CPU/Vulkan結果分別紀錄。
- [完整 WAV 延遲高於可互動門檻] → PoC 先取得量測；串流另立 change，不在此 change 中加入未驗證複雜度。
- [權重與衍生 GGUF license 標示不一致] → manifest 同時記錄原始權重與轉換檔授權來源，產品化前由專案負責人完成審查。
- [模型 provenance 包含 OpenBMB/VoxCPM] → 報告明確揭露來源；離線測試僅證明資料不外傳，不宣稱模型來源不含中國大陸。

## Migration Plan

1. 先合併不啟用 PoC flag 的 Flutter/Kotlin scaffold與tests，確認正式 build 無回歸。
2. 加入固定 revision submodule與可選 CMake target，持續保持預設關閉。
3. 以 adb 安裝 manifest 指定模型至測試手機，執行 offline smoke與20次 soak。
4. 將結果提交為不含健康內容與私人路徑的 JSON/Markdown報告。
5. 若 runtime 無法編譯、峰值記憶體超過裝置限制或20次測試不穩定，關閉 flag即可回復基線，不需資料migration。

## Open Questions

- 老師是否將「手機端離線」列為必要成果，或校內 BlueMagpie service 也可作為後續產品方案？
- 第一台標準測試裝置的型號、Android版本、RAM與SoC為何？
- 原始 BlueMagpie權重與社群GGUF轉換的商用／研究授權由誰完成最終核准？
