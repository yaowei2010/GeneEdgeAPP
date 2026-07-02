# GeneApp Android Setup Guide

This guide is for teammates who only need Android (no iOS).

## 1) Required Environment

- Flutter SDK (recommended: `3.38.9`)
- Android Studio (with Android SDK + Emulator)
- Git

## 2) Android SDK Components

Install in Android Studio -> Settings -> Android SDK:

- Android SDK Platform
- Android SDK Build-Tools
- Android SDK Platform-Tools
- Android SDK Command-line Tools (latest)
- Android Emulator (if using emulator)

## 3) Shell Environment (macOS zsh)

Add to `~/.zshrc`:

```bash
export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
export PATH="$PATH:/path/to/flutter/bin"
export PATH="$PATH:$ANDROID_SDK_ROOT/platform-tools"
export PATH="$PATH:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin"
```

Apply:

```bash
source ~/.zshrc
```

## 4) First-Time Project Setup

```bash
cd /Users/takeshi/geneapp
flutter doctor -v
flutter doctor --android-licenses
flutter pub get
```

## 5) Run Modes

### A. Main app (recommended)

```bash
flutter run -d <deviceId> -t lib/main.dart
```

This build supports in-app compute mode switching:

- `BLE` mode: App -> BLE Edge -> App -> LLM
- `Local JSON` mode: App-local mock payload -> LLM (no BLE)

### B. Local-mock entry (optional)

```bash
flutter run -d <deviceId> -t lib/main_local_mock.dart
```

## 6) Android Emulator vs Real Device

- Emulator: good for UI / Local JSON / LLM call
- Real phone: required for BLE scan/connect testing

## 7) Local JSON Payload Source

App payload loading order:

1. External Android file (priority)
2. Built-in asset fallback

### External file path (Android)

`/storage/emulated/0/Android/data/com.example.geneapp/files/local_payload.json`

### Fallback asset path

`assets/mock/local_payload.json`

## 8) Put JSON into Android Device

```bash
adb shell "mkdir -p /storage/emulated/0/Android/data/com.example.geneapp/files"
adb push /Users/takeshi/geneapp/assets/mock/local_payload.json /storage/emulated/0/Android/data/com.example.geneapp/files/local_payload.json
```

Verify:

```bash
adb shell "ls -l /storage/emulated/0/Android/data/com.example.geneapp/files/local_payload.json"
adb shell "head -n 20 /storage/emulated/0/Android/data/com.example.geneapp/files/local_payload.json"
```

## 9) Build APK

```bash
flutter build apk --release
```

Output:

`build/app/outputs/flutter-apk/app-release.apk`

Install to device:

```bash
flutter install -d <deviceId> --use-application-binary build/app/outputs/flutter-apk/app-release.apk
```

## 10) BLE Notes (Android 10)

If BLE scan fails, check:

- App permissions: Bluetooth + Location + Microphone (if voice input)
- System Location service is ON
- Developer options / USB debugging enabled (for dev install)

## 11) Common Troubleshooting

- `adb: command not found`
  - Add `platform-tools` to PATH.
- `device unauthorized`
  - Replug USB, accept RSA dialog on phone, run:
  - `adb kill-server && adb start-server`
- Flutter can run but no Android device in `flutter devices`
  - Check USB mode (File Transfer), cable quality, USB debugging, phone unlocked.
