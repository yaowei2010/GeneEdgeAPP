# GeneEdgeAPP

NCKU GeneEdgeAPP Flutter client.

## Overview

GeneEdgeAPP is a Flutter chat application that can use BLE edge-device data,
local mock payloads, and an LLM backend.

## Android Setup

See [README-ANDROID.md](README-ANDROID.md) for Android environment setup,
device installation, local payload placement, BLE notes, and troubleshooting.

## Run

```bash
flutter pub get
flutter run -d <deviceId> -t lib/main.dart
```

For local mock testing:

```bash
flutter run -d <deviceId> -t lib/main_local_mock.dart
```
