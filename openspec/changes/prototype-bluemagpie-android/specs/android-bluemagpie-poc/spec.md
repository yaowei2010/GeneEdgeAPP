## ADDED Requirements

### Requirement: Isolated Android PoC entry
The application SHALL expose the BlueMagpie diagnostic page only on Android ARM64 debug builds and MUST preserve the existing login, chat, BLE, ASR, and LLM behavior when the PoC feature is disabled.

#### Scenario: Unsupported platform
- **WHEN** the application runs on iOS, web, desktop, or a non-ARM64 Android build
- **THEN** the production navigation contains no BlueMagpie entry and existing application behavior remains unchanged

#### Scenario: Enabled Android debug build
- **WHEN** an ARM64 Android debug build enables the BlueMagpie PoC flag
- **THEN** the diagnostic page is reachable through a clearly labeled developer-only action

### Requirement: Runtime provenance report
The PoC SHALL report whether the codec-enabled runtime is compiled, the pinned runtime revision, Android ABI, backend selection, and device memory class without loading model weights.

#### Scenario: Runtime is not compiled
- **WHEN** the application was built without the codec-enabled native runtime
- **THEN** the report returns `runtime_missing` with revision and build instructions instead of crashing

#### Scenario: Runtime is compiled
- **WHEN** the application was built with runtime revision `7d5cf82cf33883bc80ec845905f5d85c5565d132`
- **THEN** the report returns `available`, `arm64-v8a`, and the selected CPU or Vulkan backend

### Requirement: App-private model validation
The PoC MUST load model weights only from application-private internal no-backup storage and SHALL validate canonical path, readability, minimum free space, expected file size, and configured SHA-256 before native initialization. GGUF weights MUST NOT be stored in Git, APK, AAB, or cloud backup artifacts. Debug sideloading MAY stage files in `/data/local/tmp`, but native initialization MUST NOT read models from that staging path.

#### Scenario: Valid model pair
- **WHEN** `BlueMagpie-Barbet-1B-q4_k_m.gguf` and `BlueMagpie-AudioVAE.gguf` match configured sizes and SHA-256 values
- **THEN** the PoC marks both files valid and permits initialization

#### Scenario: Missing or mismatched model
- **WHEN** either model is missing, unreadable, outside application-private storage, or fails size or SHA-256 verification
- **THEN** initialization remains disabled and the page identifies the failing check without exposing arbitrary filesystem paths

##### Example: model validation matrix

| Barbet | AudioVAE | Expected state |
| --- | --- | --- |
| valid | valid | `ready` |
| missing | valid | `model_missing` |
| valid | SHA mismatch | `model_checksum_mismatch` |
| external public path | valid | `model_path_rejected` |

### Requirement: Explicit native lifecycle
The native bridge SHALL expose mutually exclusive uninitialized, initializing, ready, synthesizing, cancelling, failed, and released states. Repeated initialization and release calls MUST be idempotent, and model work MUST NOT run on the Android main thread.

#### Scenario: Successful initialization
- **WHEN** validated models initialize successfully from the uninitialized state
- **THEN** the bridge enters ready state and reports elapsed milliseconds plus resident memory delta

#### Scenario: Duplicate initialization
- **WHEN** initialization is requested while the bridge is initializing or ready
- **THEN** the bridge returns the existing operation or ready status without allocating a second model context

### Requirement: Offline WAV synthesis
The PoC SHALL convert non-empty Traditional Chinese text of at most 200 Unicode scalar values into a mono 48 kHz PCM WAV in application-private cache storage and SHALL return the output path, duration, sample count, time-to-first-audio, total elapsed time, and peak resident memory.

#### Scenario: Successful synthesis
- **WHEN** a ready runtime receives `今天天氣真好，我們一起去散步吧。`
- **THEN** it produces a readable non-empty 48 kHz WAV and reports finite non-negative metrics

#### Scenario: Invalid synthesis input
- **WHEN** input is empty or exceeds 200 Unicode scalar values
- **THEN** no native generation begins and the PoC returns `invalid_text`

### Requirement: Cancellation and cleanup
The PoC SHALL allow the active synthesis to be cancelled, MUST stop accepting generated frames after cancellation, and SHALL delete partial WAV files. Releasing the page SHALL cancel active work and release native contexts.

#### Scenario: User cancels synthesis
- **WHEN** the user selects stop during synthesis
- **THEN** the operation reaches cancelled state, no partial WAV remains, and a subsequent synthesis can start without restarting the app

#### Scenario: Page is disposed
- **WHEN** the diagnostic page is disposed during initialization or synthesis
- **THEN** owned work is cancelled and model contexts are released without a native crash

### Requirement: Structured failure isolation
Every model, runtime, memory, backend, decode, file, and cancellation failure SHALL cross the Flutter boundary as a stable code plus safe message and diagnostic metadata. Native exception text, arbitrary paths, and stack memory MUST NOT be exposed as user-facing content.

#### Scenario: Native allocation fails
- **WHEN** model initialization cannot allocate required memory
- **THEN** the page reports `insufficient_memory`, remains responsive, and offers release or retry after resources are freed

#### Scenario: Vulkan initialization fails
- **WHEN** Vulkan cannot initialize on the device
- **THEN** the PoC retries once with the CPU backend or reports `backend_unavailable` without terminating the application

### Requirement: Offline and regression verification
After model installation, synthesis MUST complete with network access disabled, and disabling the PoC MUST leave existing Flutter analysis, widget tests, and Android debug build behavior unchanged.

#### Scenario: Airplane-mode synthesis
- **WHEN** validated models are installed and the device has no network connectivity
- **THEN** the fixed Chinese smoke sentence can be synthesized without outbound network access

#### Scenario: PoC disabled regression check
- **WHEN** the project builds with the BlueMagpie flag disabled
- **THEN** `flutter analyze`, `flutter test`, and the Android ARM64 debug build complete without requiring BlueMagpie source or model files
