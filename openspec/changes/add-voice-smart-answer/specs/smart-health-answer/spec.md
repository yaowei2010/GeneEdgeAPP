## ADDED Requirements

### Requirement: Unified confirmed-input path
The system SHALL process confirmed voice transcripts and typed text through the same chat submission pipeline, topic strategy, BLE or local context assembly, and `/v1/ask` request contract.

#### Scenario: Confirmed voice transcript is submitted
- **WHEN** the user sends a reviewed voice transcript
- **THEN** the system creates one user message and one smart-answer request with content identical to the reviewed composer text

### Requirement: Observable request lifecycle
The system SHALL represent each smart-answer request as queued, processing, succeeded, failed, cancelled, or timed out, and SHALL prevent repeated send actions from creating duplicate requests for the same submission.

#### Scenario: Request succeeds
- **WHEN** `/v1/ask` returns a valid non-empty answer before the configured timeout
- **THEN** the processing indicator is replaced by exactly one assistant answer associated with that request

#### Scenario: User cancels a request
- **WHEN** the user cancels an active request
- **THEN** the system stops waiting, removes the processing indicator, marks the request cancelled, and ignores any late response

#### Scenario: Request times out
- **WHEN** the configured answer timeout elapses without a valid response
- **THEN** the system preserves the user message and offers retry without duplicating the original user message

### Requirement: Backward-compatible LLM contract
The client SHALL continue to call `POST /v1/ask` with user, query, topic, variant, and Yuguard context fields, SHALL request a Traditional Chinese answer, and SHALL attach a client-generated request identifier for correlation without requiring streaming support in the MVP.

#### Scenario: Existing non-streaming backend responds
- **WHEN** the backend returns any currently supported answer shape
- **THEN** the client extracts the Traditional Chinese text answer and associates it with the originating request identifier

#### Scenario: Backend returns a non-Chinese answer
- **WHEN** the backend response is not predominantly Chinese despite the requested response language
- **THEN** the client keeps the response available, marks the language mismatch for diagnostics, and MUST NOT silently perform a second billable LLM request

### Requirement: Health answer safety
Every health answer SHALL identify itself as informational rather than a diagnosis, MUST NOT present medication changes as instructions, and SHALL direct users to qualified or emergency help when high-risk symptoms or crisis signals are present.

#### Scenario: Medication change request
- **WHEN** a user asks whether to start, stop, or change a medication dose
- **THEN** the answer avoids prescribing the change and directs the user to a physician or pharmacist

#### Scenario: Immediate high-risk signal
- **WHEN** user input contains a configured emergency or self-harm risk signal
- **THEN** the system presents an immediate safety message and locally relevant emergency-help direction even if the LLM request fails

### Requirement: Safe failure and fallback disclosure
The system SHALL distinguish BLE context failure, cloud LLM failure, malformed answer, and network unavailability, and SHALL disclose when an answer lacks the expected personalized gene context.

#### Scenario: BLE fails and cloud fallback is allowed
- **WHEN** BLE context retrieval fails and cloud fallback is enabled
- **THEN** the system requests an answer without BLE context and labels the result as lacking that personalized context

#### Scenario: LLM returns an empty or malformed answer
- **WHEN** the backend response cannot produce a non-empty supported answer
- **THEN** the system displays a recoverable error and MUST NOT expose raw response payload as health advice

### Requirement: Data-minimized diagnostics
The system SHALL record request identifier, input source, selected speech engine, coarse duration, outcome, and error category for diagnostics, and MUST NOT record raw audio, full transcript, full gene variant values, credentials, or full LLM response in production telemetry.

#### Scenario: Successful voice-originated answer
- **WHEN** a voice-originated smart-answer request succeeds
- **THEN** telemetry records the permitted metadata and excludes the transcript, raw audio, complete variants, and answer body
