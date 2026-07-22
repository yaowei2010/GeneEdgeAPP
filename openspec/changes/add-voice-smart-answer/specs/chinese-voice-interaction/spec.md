## ADDED Requirements

### Requirement: Explicit Chinese voice input lifecycle
The system SHALL represent Chinese voice input with explicit idle, listening, review, and error states, and SHALL expose only valid user actions for the current state.

#### Scenario: Voice session reaches review
- **WHEN** a user starts voice input and the recognizer returns a final non-empty Traditional Chinese transcript
- **THEN** the system enters review state and displays the transcript in the editable composer

#### Scenario: User stops listening
- **WHEN** a user stops an active voice session
- **THEN** the system stops microphone capture and retains the latest non-empty partial transcript for review

### Requirement: User confirmation before submission
The system MUST NOT submit a voice transcript to the smart-answer service until the user explicitly sends the editable composer content.

#### Scenario: Final transcript is not automatically sent
- **WHEN** speech recognition produces a final transcript
- **THEN** the transcript remains editable and no LLM request is created until the user selects send

### Requirement: Existing drafts are preserved
The system MUST NOT silently discard text already present in the composer when a voice session starts.

#### Scenario: Voice input with an existing draft
- **WHEN** the composer contains text and the user starts voice input
- **THEN** recognized text is combined with the existing draft using a visible, deterministic insertion behavior

### Requirement: Chinese recognition and recovery
The system SHALL use the device speech recognizer with locale `zh_TW` for the MVP and SHALL keep text input available after denied permission, unavailable recognition, empty speech, or recognition failure.

#### Scenario: Permission is denied
- **WHEN** the operating system denies microphone or speech-recognition permission
- **THEN** the system explains the required permission, offers the applicable settings action, and keeps the text composer usable

#### Scenario: Recognition returns no text
- **WHEN** a voice session ends without a non-empty transcript
- **THEN** the system displays a retry message and does not send a chat message

### Requirement: Chinese answer playback
Each successful assistant answer SHALL expose a playback action that speaks the displayed Traditional Chinese answer through an available system TTS voice and SHALL expose stop and replay actions. Playback SHALL be manual by default; the user SHALL be able to enable automatic playback as a persisted preference.

#### Scenario: Manual playback succeeds
- **WHEN** the user selects play on an assistant answer and a `zh-TW` TTS voice is available
- **THEN** the system speaks that answer and visibly identifies it as the active playback item

#### Scenario: Automatic playback is disabled
- **WHEN** a new assistant answer arrives while automatic playback is disabled
- **THEN** the answer remains silent and its play action remains available

#### Scenario: Another answer starts playing
- **WHEN** playback is active and the user selects play on another assistant answer
- **THEN** the system stops the current utterance before speaking the newly selected answer

### Requirement: TTS availability and content normalization
The system SHALL check for a compatible Chinese TTS language before playback, SHALL preserve the visible text answer when TTS is unavailable, and SHALL convert non-speech Markdown syntax into a speech-safe utterance without changing the visible answer.

#### Scenario: Chinese TTS voice is unavailable
- **WHEN** the device has no compatible `zh-TW` or configured Chinese TTS voice
- **THEN** the system keeps the text answer visible and displays an actionable playback-unavailable message

#### Scenario: Answer contains Markdown
- **WHEN** an assistant answer contains headings, list markers, links, or code formatting
- **THEN** playback uses normalized readable text while the original Markdown remains displayed

### Requirement: Audio focus and lifecycle cleanup
The system MUST prevent microphone capture and answer playback from running simultaneously and MUST stop owned recording or playback resources when the chat view is disposed. The system MUST NOT persist or upload raw microphone audio or synthesized audio files.

#### Scenario: User starts voice input during playback
- **WHEN** an answer is playing and the user starts voice input
- **THEN** the system stops playback before opening the microphone

#### Scenario: Chat view is disposed
- **WHEN** the chat view is disposed during capture or playback
- **THEN** active audio is stopped and owned resources are released
