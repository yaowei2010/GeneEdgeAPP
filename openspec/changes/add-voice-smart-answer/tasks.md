## 1. 語音服務基礎

- [ ] 1.1 依「Introduce injectable ASR and TTS services」建立 `SpeechInputService`、`AnswerSpeechService` 與 fake adapters，使 widget 不直接持有平台 plugin，並以 service unit tests 驗證狀態事件、錯誤映射與 dispose contract。
- [ ] 1.2 導入並鎖定相容的系統 TTS adapter、補齊 Android TTS service query，使 iOS/Android 能查詢 `zh-TW` voice 並執行 speak/stop；以 platform smoke test 與 dependency build 驗證。

## 2. 中文語音輸入

- [ ] 2.1 實作「Explicit Chinese voice input lifecycle」與「Chinese recognition and recovery」，使 `zh_TW` 輸入具備 idle/listening/review/error 狀態且所有失敗都保留文字輸入；以 `voice_input_state_test` 與 permission/unavailable manual cases 驗證。
- [ ] 2.2 依「Use review-before-send and deterministic draft merging」完成「User confirmation before submission」與「Existing drafts are preserved」，使辨識結果可編輯、絕不自動送出、既有 draft 不被清除；以 widget tests 覆蓋 partial/final/stop/cancel 與 draft merge。

## 3. 中文智慧回答

- [ ] 3.1 依「Keep the LLM contract text-based and request Traditional Chinese」完成「Unified confirmed-input path」與「Backward-compatible LLM contract」，使 typed/voice 都經同一 pipeline 並在 `POST /v1/ask` 加入 `request_id`、`input_source`、`response_language: zh-TW`；以 API contract tests 驗證 payload 與既有 response shapes。
- [ ] 3.2 依「Add request identity and a client request state machine」完成「Observable request lifecycle」，使每次送出只有一個 queued/processing/succeeded/failed/cancelled/timed-out 結果，late response 不得寫回且 retry 不複製 user message；以 controller tests 驗證 duplicate/cancel/timeout/retry。
- [ ] 3.3 實作「Safe failure and fallback disclosure」，使 BLE、network、malformed answer 與 wrong-language 狀況各自可恢復，且缺少個人化 context 時明確揭露；以 controller/API error matrix tests 驗證。

## 4. 中文語音播放

- [ ] 4.1 依「Use manual playback by default with one active utterance」完成「Chinese answer playback」，使每則 assistant answer 有 play/stop/replay、預設不自動播放、可保存 auto-play preference，且同時只有一則播放；以 playback widget tests 與 preference reload test 驗證。
- [ ] 4.2 依「Normalize answer text only for speech」完成「TTS availability and content normalization」，使 Markdown 顯示不變、TTS 使用可讀文字與句界 chunk，中文 voice 不可用時仍保留文字；以 normalizer table tests 與 unavailable-voice service test 驗證。
- [ ] 4.3 完成「Audio focus and lifecycle cleanup」，使麥克風與 TTS 互斥、切換頁面或 dispose 時立即停止，且不產生持久音訊檔；以 audio-coordination tests 與 iOS/Android lifecycle smoke test 驗證。

## 5. 健康安全與隱私

- [ ] 5.1 依「Apply layered health safety controls」完成「Health answer safety」，使一般回答含資訊性界線、用藥問題引導專業人員、高風險輸入在 API 失敗時仍顯示本地安全指引；以 versioned health-safety fixture tests 驗證。
- [ ] 5.2 依「Minimize persisted and diagnostic data」完成「Data-minimized diagnostics」，使 production events 僅含允許 metadata，排除 raw audio、transcript、完整 variants 與 answer body；以 log-redaction tests 及 release-mode review 驗證。

## 6. 整合與發布

- [ ] 6.1 以 feature flags 逐步啟用中文 ASR、中文 LLM output 與 TTS，並驗證關閉旗標時既有文字聊天不變；以 enabled/disabled integration tests 驗證 rollback contract。
- [ ] 6.2 執行 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`、`spectra validate add-voice-smart-answer`，再於一台 iOS 與一台 Android 完成中文輸入、API 回答、播放、停止、失敗復原的 manual checklist，全部通過後才可發布。
