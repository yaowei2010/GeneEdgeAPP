## Why

老師希望 GeneEdge 評估 BlueMagpie-TTS 在 Android 手機端離線產生台灣華語語音的可行性，但目前 App 是 Flutter，官方 `llama.rn` 則以 React Native 為目標，且 TTS 支援只存在尚未主線化的 codec 分支。需要先用隔離 PoC 驗證公開 runtime、模型載入、記憶體、延遲與音訊正確性，才能決定是否納入正式產品。

## What Changes

- 新增 Android-only、`arm64-v8a` 的 BlueMagpie-TTS 診斷入口，不改變正式聊天與既有系統 TTS 行為。
- 以 Flutter `MethodChannel`/`EventChannel` 對接 Android native bridge，native 層再呼叫固定版本的 codec-enabled C++ runtime。
- 模型權重不進 Git 或 APK；PoC 驗證外部安裝的 Barbet GGUF 與 AudioVAE GGUF、檔案大小、SHA-256 與可讀性。
- 提供初始化、產生 WAV、停止、釋放與結構化錯誤狀態，並顯示模型載入時間、合成時間、首音時間、輸出長度與 process memory。
- 在 runtime 未編入或模型不存在時，PoC 必須正常啟動並清楚回報不可用，不得讓 App crash。
- 固定研究基線為 `mybigday/llama.rn` codec branch commit `7d5cf82cf33883bc80ec845905f5d85c5565d132`；正式導入前重新審查來源、授權與 upstream 狀態。

## Capabilities

### New Capabilities

- `android-bluemagpie-poc`: Android ARM64 裝置上的 BlueMagpie runtime 探測、模型驗證、離線 WAV 合成、取消、錯誤處理與效能量測。

### Modified Capabilities

（無）

## Impact

- Affected specs: `android-bluemagpie-poc`
- Affected code:
  - New: `lib/bluemagpie_tts.dart`, `lib/bluemagpie_poc_page.dart`, `test/bluemagpie_tts_test.dart`, `android/app/src/main/kotlin/com/example/geneapp/BlueMagpieTtsPlugin.kt`, `android/app/src/main/cpp/bluemagpie_bridge.cpp`, `docs/bluemagpie-android-poc.md`
  - Modified: `lib/main.dart`, `android/app/src/main/cpp/CMakeLists.txt`, `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, `.gitignore`
  - Removed: none
- External systems: BlueMagpie GGUF 權重來源、codec-enabled `llama.rn` C++ source、Android NDK/Vulkan 或 CPU backend。
