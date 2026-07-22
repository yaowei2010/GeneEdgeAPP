## Why

GeneEdge 已具備基礎中文語音轉文字與 LLM API，但目前缺少一致的錄音狀態、辨識結果確認、錯誤復原、中文回答保證與語音播放，尚不足以作為完整的語音問答功能。現在應把輸入辨識、LLM 中文回答與文字轉語音整合成可測試、可觀測且保護健康資料的端到端體驗。

## What Changes

- 將麥克風輸入整理為明確的「待命、聆聽、轉錄、可編輯確認、失敗」流程，辨識文字預設由使用者確認後才送出。
- MVP 使用裝置的 `speech_to_text` 支援繁體中文；保留文字輸入與權限拒絕、辨識不可用、無語音結果時的復原路徑。
- 將確認後的 transcript 送入既有聊天控制器與 `/v1/ask`，統一處理等待、逾時、取消、重試及雲端／BLE fallback 的呈現。
- 要求 LLM API 回覆繁體中文文字，並在每則 assistant 回覆提供中文語音播放、停止及重播控制。
- 透過可替換的 TTS service 使用 iOS／Android 系統語音，中文語音不可用時保留文字答案並提示使用者。
- 為 LLM 健康回答定義主題脈絡、資料最小化、醫療免責、高風險訊號與安全失敗規則。
- 補上語音與智慧回答的事件紀錄、效能指標及單元／元件／整合測試，但不得記錄原始音訊或完整敏感內容。

## Capabilities

### New Capabilities

- `chinese-voice-interaction`: 中文語音辨識、結果確認、中文回答播放、播放控制、錯誤處理及音訊隱私行為。
- `smart-health-answer`: 從確認後輸入到個人化 LLM 健康回答的請求生命週期、答案安全、取消重試與可觀測性。

### Modified Capabilities

<!-- 目前尚無既有 specs，無修改項目。 -->

## Impact

- Flutter：`lib/chat_room_page.dart` 的 composer/voice UI 與回答泡泡、`lib/chat_controller.dart` 的對話狀態、`lib/api_service.dart` 的請求生命週期，以及新增可注入的 ASR/TTS service 抽象。
- Native：iOS／Android 沿用系統中文語音辨識與文字轉語音能力；Android 需補上 TTS service query 設定。
- Backend：沿用 `/v1/ask` payload；若要支援真正取消、串流與 request tracing，需後續擴充 API 契約。
- Data/privacy：transcript 與回答仍屬健康對話資料；原始音訊與合成音檔預設不持久化、不上傳，診斷紀錄需去識別化。
- Dependencies：沿用 `speech_to_text`，新增跨平台系統 TTS adapter（建議 `flutter_tts`）並在導入時鎖定已驗證版本。
