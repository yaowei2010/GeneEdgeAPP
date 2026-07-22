## Context

GeneEdge is a Flutter chat client. `ChatRoomPage` currently owns a `SpeechToText` instance and writes `zh_TW` partial results directly into the composer; starting capture clears the existing draft. `ChatController.sendUserMessage` already routes text through topic-specific strategies, BLE or local payload context, and `ApiService.askLlm` at `POST /v1/ask`, but the synchronous request can wait up to 600 seconds and has no user cancellation identity. The app has no text-to-speech dependency or answer playback state.

The target scope is now limited to Chinese voice input, Traditional Chinese LLM text output, and Chinese text-to-speech playback. Answers concern health and genetic context, so transcript handling, personalized-context disclosure, high-risk fallback, and production logging require explicit contracts.

## Goals / Non-Goals

**Goals:**

- Deliver a reliable `zh_TW` voice-to-reviewed-text-to-Chinese-answer flow by reusing the current recognizer and `/v1/ask`.
- Add manual answer playback with stop and replay, plus an optional persisted auto-play preference.
- Separate ASR, TTS, composer UI, and conversation orchestration so each can be tested with fakes.
- Make LLM requests cancellable from the user's perspective, retryable, correlated, and safe on stale responses.
- Protect health and genetic data and provide deterministic high-risk fallback behavior.

**Non-Goals:**

- Taiwanese/Hokkien recognition, offline ASR models, or custom native ASR engines.
- Realtime full-duplex conversation, wake words, speaker identification, or continuous background recording.
- Streaming tokens in the MVP; this requires a separately versioned backend transport contract.
- On-device LLM inference, custom cloned voices, generated audio-file storage, or audio sharing/export.
- Diagnosing disease, replacing clinicians, or automatically changing medication.

## Decisions

### Introduce injectable ASR and TTS services

Define a `SpeechInputService` that exposes availability, explicit session states, partial/final transcripts, typed errors, and `start(locale)`, `stop`, and `cancel`. It wraps the existing `speech_to_text` package. Define a separate `AnswerSpeechService` that exposes supported languages/voices, playback state, `speak(messageId, text, locale)`, `stop`, and `dispose`.

Use a maintained Flutter adapter over iOS `AVSpeechSynthesizer` and Android `TextToSpeech`; `flutter_tts` is the initial candidate because it exposes language availability, voices, speak, pause, stop, and completion callbacks on both target platforms. The dependency version is locked only after compatibility testing with this repository's Flutter, Android SDK, and iOS deployment targets. Direct plugin ownership in widgets was rejected because audio focus, lifecycle, and deterministic tests would remain coupled to rendering.

### Use review-before-send and deterministic draft merging

Starting recognition snapshots the current composer draft. Voice partials update only the voice segment; the rendered composer is `draft + separator + voice segment`. A final transcript enters review and is never auto-submitted. Cancel restores the snapshot; stop keeps the latest non-empty segment.

Auto-send was rejected because health terms and medication names require correction before becoming model input.

### Keep the LLM contract text-based and request Traditional Chinese

The client sends the reviewed text through the existing pipeline and adds `response_language: zh-TW`, `request_id`, and `input_source` (`typed` or `voice_zh_tw`) as backward-compatible fields to `POST /v1/ask`. Topic system prompts are updated to require Traditional Chinese. The client accepts existing answer response shapes and treats the returned answer as the single source for both the visible Markdown and TTS normalization.

The client does not automatically issue a second LLM call when the response language is wrong because that can duplicate cost and produce inconsistent answers. It records a metadata-only language mismatch and preserves the visible response for retry.

### Use manual playback by default with one active utterance

Every successful assistant answer has play/stop/replay controls. Manual playback is the default to avoid unexpected disclosure of sensitive health content in shared spaces. Users can explicitly enable auto-play; the setting is persisted locally. Only one message can own playback. Starting another answer stops the current utterance, and starting microphone capture always stops TTS first.

Pause is exposed only where the platform adapter provides reliable semantics; stop and replay are the cross-platform baseline because Android pause behavior can vary by engine. Playback failure never removes or changes the visible answer.

### Normalize answer text only for speech

The visible response continues to render Markdown. Before TTS, a pure `SpeechTextNormalizer` removes Markdown control syntax, expands or skips URLs, turns lists/headings into natural pauses, and removes code blocks or diagnostic metadata that are unsuitable for speech. It does not summarize, translate, or call the LLM. Long answers are divided into sentence-boundary chunks so stop/replay and platform input limits remain predictable.

Speaking raw Markdown was rejected because list markers, URLs, and code fragments create poor or misleading audio.

### Add request identity and a client request state machine

Each submission receives a UUID `request_id`. `ChatController` owns request state and maps a single user message to at most one active assistant request. Cancellation aborts the HTTP operation when supported and always invalidates the local request token so late BLE or cloud results cannot mutate the conversation. Retry reuses the user message content but creates a new request ID.

The existing `/v1/ask` remains non-streaming for MVP compatibility. The answer timeout becomes configurable and suitable for interactive use; timeout and retry are visible states rather than a 600-second indefinite typing bubble.

### Apply layered health safety controls

Topic prompts continue to supply domain constraints and Traditional Chinese output instructions. Before the network call, a small versioned high-risk ruleset identifies emergency and self-harm signals and makes an immediate local safety panel available. The backend remains responsible for fuller safety classification, while the client validates that an answer is non-empty and appends the product's informational-health notice consistently. TTS reads the safety guidance but omits non-content UI labels.

Relying only on a prompt was rejected because network and model failures must not suppress urgent safety direction. The local ruleset is a safety fallback, not a diagnostic classifier.

### Minimize persisted and diagnostic data

Raw microphone audio is never persisted or uploaded by the app. Confirmed transcripts and assistant answers retain the current local chat persistence behavior; partial and cancelled transcripts are not persisted. TTS synthesizes directly to device audio output and does not generate a stored file. Production telemetry contains only request ID, input source, coarse timings, topic, outcome, playback outcome, and error category. Current debug request logging must redact transcript, variants, and answer content before release builds.

## Implementation Contract

**Behavior:** A user can start and stop Traditional Chinese voice recognition, review or edit the transcript, send it through the existing conversation flow, receive a Traditional Chinese text answer, and play/stop/replay that answer. Starting voice does not erase a draft. TTS is manual by default; optional auto-play is explicit and persisted. Text input and visible answers remain usable after ASR, LLM, or TTS failure.

**Interfaces and data:**

- `SpeechInputService` exposes availability, session state, typed errors, partial/final transcript events, and `start(locale: zh_TW)`, `stop`, and `cancel`.
- `AnswerSpeechService` exposes TTS availability/voices, current message ID, playback state, and `speak`, `stop`, and `dispose`.
- Chat submission adds `request_id`, `input_source`, and `response_language: zh-TW` while retaining existing user, query, topic, variant, and Yuguard fields in `POST /v1/ask`.
- Request and playback state are keyed by identifiers; cancelled, replaced, or timed-out work cannot append an answer or continue speaking.
- Android's manifest declares the TTS service query required for supported target versions; iOS uses the system synthesizer through the adapter.

**Failure modes:** Permission denial, unavailable Chinese ASR, empty transcript, timeout, cancellation, BLE failure, network failure, malformed LLM output, wrong response language, unavailable Chinese TTS voice, and playback engine failure produce separate recoverable UI states. TTS failures retain the text answer; ASR failures retain typed input; only allowed cloud fallback occurs.

**Acceptance criteria:** Widget tests cover input state transitions, draft merging, per-message playback controls, single-active-playback behavior, and auto-play default; controller tests cover duplicate suppression, cancellation, late-response rejection, retry, timeout, and fallback disclosure; API tests cover request ID, `response_language`, and supported answer shapes; service tests cover language availability, Markdown normalization, long-text chunking, audio mutual exclusion, and dispose cleanup. `flutter analyze`, `flutter test`, `spectra validate add-voice-smart-answer`, and iOS/Android manual smoke tests pass before release.

**Scope boundaries:** The change includes device Traditional Chinese recognition, review-before-send, Traditional Chinese text output, system TTS playback, unified request state, safety fallback, redacted diagnostics, and tests. Taiwanese/Hokkien ASR, offline ASR, streaming, continuous listening, custom voices, saved audio, and on-device LLM are excluded.

## Risks / Trade-offs

- [Chinese ASR and TTS quality vary by OS, device, and installed voices] → Check capabilities at runtime, retain editing/text fallback, and test the target device matrix.
- [Auto-play can disclose sensitive health content] → Keep it off by default, make the setting explicit, and stop audio immediately when leaving the chat.
- [Long Markdown answers can sound unnatural or exceed engine limits] → Normalize locally, chunk at sentence boundaries, and test health-domain examples.
- [Client cancellation cannot guarantee server computation stops] → Abort locally where possible, ignore stale responses by request ID, and later add backend cancellation if cost requires it.
- [Keyword safety rules create false positives or miss paraphrases] → Keep local rules conservative, use them only for immediate fallback, and retain backend safety classification.
- [Personalized genetic context can leak through logs] → Default to metadata-only telemetry and add automated redaction tests.

## Migration Plan

1. Add ASR/TTS abstractions and fake implementations behind a disabled feature flag; preserve existing text chat.
2. Fix the composer voice lifecycle and enable reviewed `zh_TW` input for internal builds.
3. Update prompts/API payloads for Traditional Chinese and enable request ID, timeout, cancel, and retry behavior.
4. Add per-answer TTS controls with manual playback default, Markdown normalization, and audio mutual exclusion.
5. Complete safety/privacy review and iOS/Android smoke tests, then enable the feature gradually.
6. Roll back by disabling voice input and TTS flags; text chat and the existing non-streaming `/v1/ask` path remain available.

## Open Questions

- Must the first release support both `zh-TW` and `zh-CN`, or only Traditional Chinese used in Taiwan?
- Should auto-play remain a user setting, or be omitted entirely from the first release?
- What interactive timeout target and answer-latency SLO can the current backend meet under load?
- Which iOS/Android versions and device models define the supported release matrix?
- What user consent and retention policy applies to confirmed transcripts and locally persisted chat history?
