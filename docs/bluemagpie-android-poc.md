# 台灣藍鵲 TTS Android PoC

此 PoC 的單一目標是：在 Android ARM64 手機輸入中文文字，由手機端離線產生
48 kHz mono WAV 並播放。它不會把模型放進 Git/APK，也不會呼叫雲端 TTS。

## 下載模型

固定使用 GGUF revision `37ab65a2836e6cf5780f2e5566ae77ca5967982f`：

- `BlueMagpie-Barbet-1B-q4_k_m.gguf`
  - 下載：<https://huggingface.co/hans00/BlueMagpie-TTS-GGUF/resolve/37ab65a2836e6cf5780f2e5566ae77ca5967982f/BlueMagpie-Barbet-1B-q4_k_m.gguf?download=true>
  - bytes：`693008576`
  - SHA-256：`c8e66535e9ee3b114a9be05ac404cb9585910865718095a3914c2b51c4d5462f`
- `BlueMagpie-AudioVAE.gguf`
  - 下載：<https://huggingface.co/hans00/BlueMagpie-TTS-GGUF/resolve/37ab65a2836e6cf5780f2e5566ae77ca5967982f/BlueMagpie-AudioVAE.gguf?download=true>
  - bytes：`1884843552`
  - SHA-256：`de3acf2f77842aa0cd7a958bf9ce5c549b94db0c7930776f320ad6152e1e86f6`

macOS 可先驗證：

```sh
shasum -a 256 BlueMagpie-Barbet-1B-q4_k_m.gguf BlueMagpie-AudioVAE.gguf
```

## 建置測試 APK

先初始化固定 C++ submodule：

```sh
git submodule update --init third_party/llama.rn-codec
```

同時開啟 Dart 入口與 Android native flag：

```sh
ORG_GRADLE_PROJECT_bluemagpiePoc=true \
flutter build apk --debug --target-platform android-arm64 \
  --dart-define=BLUEMAGPIE_POC=true
```

產物：`build/app/outputs/flutter-apk/app-debug.apk`。預設的一般 build 仍關閉 PoC。
flag-on debug APK 使用獨立 application ID `com.example.geneapp.bluemagpie`，手機上會顯示
為「GeneEdge 藍鵲測試」，可與既有 `com.example.geneapp` 同時安裝且不共用 App 資料。

## 安裝模型到手機

先安裝 APK、啟動 App 一次，再透過 Android SDK 的 adb 執行：

```sh
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell mkdir -p /sdcard/Android/data/com.example.geneapp.bluemagpie/files/models/bluemagpie
adb push BlueMagpie-Barbet-1B-q4_k_m.gguf \
  /sdcard/Android/data/com.example.geneapp.bluemagpie/files/models/bluemagpie/
adb push BlueMagpie-AudioVAE.gguf \
  /sdcard/Android/data/com.example.geneapp.bluemagpie/files/models/bluemagpie/
```

若系統封鎖直接寫入 `Android/data`，可用 Android Studio 的 Device Explorer 將兩個
檔案放入相同的 app-specific external files 目錄。不要改檔名。

## 手機操作

1. 登入頁選擇 `Continue without account`。
2. 進入聊天頁後開啟左側選單。
3. 選擇「藍鵲 TTS 測試」。
4. 第一輪請選 CPU，輸入最多 200 個 Unicode 字元。
5. 按「合成並播放」。App 會依序 probe runtime、驗證兩個模型、載入、合成、
   將完整 WAV 寫到 private cache，再用 Android `MediaPlayer` 播放。

固定 smoke sentence：`今天天氣真好，我們一起去散步吧。`

## 已完成的自動驗證（2026-07-22）

- flag-off：`flutter analyze`、19 個 Flutter tests、ARM64 debug APK 均通過。
- Android JVM：model manifest/path/size/SHA/redaction 與 plugin worker/playback tests 通過。
- flag-on：pinned codec branch 已由 NDK 28.2 完整編譯；APK 包含
  `libgeneedge_bluemagpie.so`、`librnllama.so`，不含 `.gguf`。
- flag-on APK 已以 Dart + Gradle 兩個 flag 建置成功。

尚未完成的是實體手機上的模型載入、中文 WAV、播放與 20 次 soak；因此目前不能把
PoC 宣告為產品可用。Vulkan fallback 也尚未驗收，第一輪請使用 CPU。

### 真機安裝紀錄（2026-07-22）

- Pixel 10 Pro、Android 16 / SDK 36、ARM64。
- `com.example.geneapp` 與 `com.example.geneapp.bluemagpie` 已驗證可同時安裝。
- 測試 App cold start 成功；手機端兩個 GGUF 的 byte size 與 SHA-256 均符合 manifest。
- 中文合成、播放與重複 soak 仍待使用者在診斷頁觸發及觀察。

## 來源與限制

runtime 固定為 `mybigday/llama.rn` codec commit
`7d5cf82cf33883bc80ec845905f5d85c5565d132`。App 不包含 React Native、JSI 或 npm。
模型轉換頁宣告 Apache-2.0，但原始 OpenFormosa 模型卡標記為 `other`，且架構沿用
OpenBMB/VoxCPM；正式發布前仍須完成授權與來源審查。詳見
`docs/bluemagpie-third-party-licenses.md`。
