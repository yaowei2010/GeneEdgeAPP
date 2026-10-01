## ADDED Requirements

### Requirement: Upper USB form shares the existing GeneLLM control
The existing upper USB settings form SHALL expose a GeneLLM switch near its top with explicit LLM ON/OFF text and a description of enabled completed-job submission versus offline-only execution. Its value and setter SHALL use the existing ChatController GeneLLM state and preference, with live synchronization to the retained drawer control. No second USB-specific enable flag or preference SHALL be introduced. The form switch SHALL be disabled during C computation or LLM waiting and without an actionable callback. Opening the form, toggling the switch and preference restoration SHALL NOT compute, invoke HTTP or retrospectively submit a completed offline result. Existing per-submission snapshots, JSON visibility, USB confirmation and retry behavior SHALL remain unchanged. The form SHALL remain bounded and scrollable with the keyboard open.

#### Scenario: Shared setting through either entry
- **WHEN** the idle user changes GeneLLM in the USB form or the existing drawer
- **THEN** both entries SHALL reflect the same controller state and explicit ON/OFF label without computation or transmission.

##### Example: Enable without sending
- **GIVEN** a ready USB, GeneLLM=false, runCalls=0 and LLM calls=0
- **WHEN** the user opens the upper form and enables GeneLLM
- **THEN** the form SHALL show LLM ON, the drawer SHALL show GeneLLM on, both call counts SHALL remain zero and the next submission SHALL capture enabled=true.

#### Scenario: Busy form control
- **WHEN** USB C computation or its LLM request is pending
- **THEN** the form GeneLLM switch SHALL be disabled while JSON display remains independently switchable, and the submitted enable snapshot SHALL remain unchanged.

The completed-USB LLM requirements below SHALL supersede the earlier pre-LLM boundary and HTTP prohibition for chat jobs only. Legacy independent computation SHALL remain offline. USB requests, diagnostic results and responses SHALL remain ephemeral; existing ordinary chat behavior SHALL remain unchanged.

### Requirement: Reuse existing LLM API for completed USB chat jobs
The chat SHALL capture the existing GeneLLM enabled flag at USB submission. When enabled, a fully validated current completed locus job SHALL submit its API request exactly once through the existing ApiService.askLlm endpoint, JSON contract and response parser, without invoking BLE or Local JSON computation. Disabled submissions SHALL stop at offline result presentation. Request identity and locus counts SHALL come from the completed job snapshot; no-calls SHALL be excluded from the three identical variant lists without losing input/no-call counts. Diagnostic fields, raw data and source URIs SHALL NOT be transmitted. USB request logging and chat-history persistence SHALL remain disabled. JSON display preference SHALL NOT affect submission or cause resubmission. Insertion, source confirmation and partial, failed, cancelled or invalid computation SHALL NOT invoke LLM.

#### Scenario: Enabled submission completes
- **WHEN** a GeneLLM-enabled USB chat job completes with a valid API export
- **THEN** the existing LLM API SHALL be called once, its parsed answer SHALL appear in the original chat message stream, and neither BLE nor mock computation SHALL run.

##### Example: Preserve no-call counts
- **GIVEN** a completed 77-locus alcohol job with 70 calls and seven no-calls, user_id=u1 and query="我能喝酒嗎"
- **WHEN** the enabled job is sent to LLM
- **THEN** all three variant lists SHALL contain the same 70 entries, variant_input_count=77, variant_used_count=70, no_call_count=7, yuguard=null, and the captured identity/query SHALL be preserved.

#### Scenario: Disabled submission and visibility changes
- **WHEN** GeneLLM was disabled at submission or the user changes JSON visibility after completion
- **THEN** disabled submissions SHALL cause no HTTP, and visibility changes SHALL cause no additional computation or request, without hiding a valid LLM answer.

### Requirement: Job-scoped USB LLM responses and explicit retry
USB LLM waiting, answers and failures SHALL render as ephemeral entries in the original chat using existing bubble rendering. Computation and LLM waiting SHALL block duplicate sends. Duplicate completion events SHALL NOT duplicate requests. Failed LLM requests SHALL leave valid C results available and offer explicit retry of the same request only while the job is valid and GeneLLM is enabled; retry SHALL NOT rerun C or silently fall back to other data. Cancellation, removal, source/topic change, logout and disposal SHALL invalidate response generation and suppress late success and failure. Old callbacks SHALL NOT clear newer request state. No automatic retry, TTS, clipboard writes or persistence SHALL occur. Already transmitted requests SHALL NOT be represented as retractable.

#### Scenario: Retry a failed request
- **WHEN** LLM HTTP fails for a still-valid completed USB job and the user explicitly retries
- **THEN** one additional request SHALL use the same snapshot without a new C run; pending state SHALL block another simultaneous retry.

##### Example: Failure then retry
- **GIVEN** runCalls=1 and one failed LLM request for job j1
- **WHEN** the user presses retry once and receives answer="測試回覆"
- **THEN** runCalls SHALL remain 1, LLM request count SHALL equal 2, and one current answer SHALL be visible without persisted genetic payloads.

#### Scenario: Ignore invalidated replies
- **WHEN** a pending request's job is invalidated by removal, cancellation, source/topic change, logout or page disposal
- **THEN** pending/retry/result bubbles SHALL clear and its later success or failure SHALL NOT appear or alter a newer job.

The independent query-page and 143-query requirements below SHALL remain the legacy/advanced workflow. The added chat workflow SHALL use the separate joint-locus mode defined below, with 77 locus results derived from the unchanged 143-record reference panel. Legacy per-query results SHALL NOT substitute for joint-locus evidence or API export. The USB-source chat message flow requirement added on 2026-10-01 SHALL supersede the previously implemented explicit USB-offline switch and replacement chat body; its pre-LLM boundary and ephemeral-result restrictions SHALL remain unchanged.

The dismissible insertion confirmation below SHALL take precedence over the earlier icon-tap behavior: tapping the USB icon SHALL reopen confirmation, while the existing settings arrow SHALL continue to expand the upper settings panel. Source metadata persistence SHALL be distinct from the prohibition on persisting genetic results.

The topic-independent insertion and compact result requirements below SHALL take precedence over earlier inline locus/debug presentation. A persisted display-preference boolean SHALL be distinct from genetic-result persistence; API and diagnostic payloads SHALL remain ephemeral.

### Requirement: Topic-independent USB insertion prompting
The foreground chat room SHALL display insertion confirmation upon detection of a mounted removable USB without requiring topic selection, set availability, asset completion or other user interaction. Mounted-volume readiness SHALL NOT be represented as an authorized source or a completed scan. Pending source discovery SHALL be shown as pending within confirmation rather than delaying it until topic interaction. First entry with USB attached and return to foreground SHALL recheck attachment state. A new attachment detected during a busy job or another active route SHALL be processed only after the chat is foreground and idle, if still attached. Dismissal deduplication, icon reopening, root authorization rules, removal/logout/disposal cleanup and stale-callback rejection SHALL remain unchanged. Insertion SHALL NOT select alcohol automatically, run C, open the system picker automatically or invoke HTTP.

#### Scenario: Insert without selecting a topic
- **WHEN** USB is detected in the foreground idle chat with no topic selected, an unsupported topic, or a pending or failed panel load
- **THEN** one dismissible USB confirmation SHALL appear without a topic tap, and computation SHALL remain blocked until source confirmation and a valid ready set.

##### Example: Pending alcohol asset
- **GIVEN** no USB, a pending alcohol asset future and runCalls=0
- **WHEN** mounted USB ABCD-1234 is reported without completing the asset or tapping the topic selector
- **THEN** USB confirmation SHALL appear, runCalls SHALL remain zero, and repeated refresh SHALL NOT create another dialog.

#### Scenario: Deferred foreground confirmation
- **WHEN** a new USB is detected while a job is busy or the chat route is not current
- **THEN** confirmation SHALL wait until chat foreground idle state; a USB removed before then SHALL NOT produce a stale dialog.

##### Example: Return to the chat
- **GIVEN** another route is open and USB ABCD-1234 is detected
- **WHEN** the user returns to the idle chat without changing its topic
- **THEN** one insertion confirmation SHALL appear if ABCD-1234 remains mounted.

### Requirement: Compact API JSON presentation and visibility preference
A completed chat USB job SHALL render only a compact completion state, the unchanged API request JSON and explicit copy controls in its message-stream result card. JSON presentation SHALL be height-bounded and scrollable. Per-locus counts, candidate posteriors and full diagnostic reports SHALL NOT be rendered in the chat result card. The existing upper settings panel SHALL expose a display-JSON toggle defaulting to enabled for a new installation and privately persist only that boolean. Preference loading SHALL NOT override a newer user change; unresolved preference loading SHALL NOT expose JSON text. Disabled display SHALL remove JSON content from both rendered widgets and accessibility semantics for current and subsequent results. Display toggling SHALL NOT change counts, genotypes, job snapshots, payload serialization or execution, and SHALL NOT trigger C, HTTP, TTS, automatic copying or payload persistence. Restart SHALL restore only the preference, not genetic results. Re-enabling display SHALL expose only the still-valid latest payload.

#### Scenario: Hide current and future JSON
- **WHEN** the user disables display in upper settings
- **THEN** the current and subsequent successful cards SHALL show only a short completed/hidden state without JSON content; explicit re-enabling SHALL show a still-valid latest payload without rerunning computation.

##### Example: Same payload after visibility change
- **GIVEN** one completed 77-locus alcohol job, a valid API payload and runCalls=1
- **WHEN** display is disabled and enabled again
- **THEN** the payload SHALL remain identical, runCalls SHALL remain 1, no automatic clipboard or HTTP action SHALL occur, and no 77-locus detail cards SHALL appear.

#### Scenario: Display preference survives restart without results
- **WHEN** display is disabled and the chat is recreated or the app restarts
- **THEN** display SHALL remain disabled, but no previous JSON or genetic result SHALL be restored from private storage.

##### Example: Boolean-only storage
- **GIVEN** display was disabled after a completed job
- **WHEN** preferences are inspected and a new chat page is opened
- **THEN** the feature SHALL have stored only its display boolean, and no query, variant, genotype, diagnostic or API payload SHALL have been persisted.

### Requirement: Explicit bounded chat diagnostics
Debug instrumentation and per-job debug snapshots SHALL remain unchanged. When the latest valid job has a debug report, upper settings SHALL offer an explicit action to open a bounded scrollable diagnostic view with stage timing, a research warning and explicit copy controls. Reports SHALL NOT automatically expand into the message stream. Debug-disabled jobs SHALL NOT expose a debug report. Cancellation, removal, source/topic changes, logout and page disposal SHALL invalidate reports and close a diagnostic view showing an invalidated job; stale events SHALL NOT restore it. Hiding API JSON SHALL NOT change debug instrumentation or transmit either payload.

#### Scenario: Open timing only on request
- **WHEN** a debug-enabled 77-locus chat job completes
- **THEN** the message stream SHALL omit its diagnostic report, and explicit upper-settings inspection SHALL show its valid stage times without additional computation or networking.

##### Example: Removal during inspection
- **GIVEN** the diagnostic view is open for the latest completed USB job
- **WHEN** that USB is removed
- **THEN** the view SHALL close and its copyable report SHALL be cleared; a late event SHALL NOT reopen or restore it.

### Requirement: USB root authorization and source restoration
Android SHALL reuse valid persisted read-only SAF grants for mounted removable USB volumes and SHALL default a new authorization picker to the selected USB volume root using its UUID root document URI on supported versions. Initial location SHALL NOT grant permission or confirm the system picker. The UI SHALL identify the actual authorized scope, including existing subfolder-only grants, and SHALL expose a root-authorization action. Provider restrictions SHALL be surfaced without requesting write or all-files access, selecting primary storage, or claiming unauthorized root access. Source discovery SHALL scan only authorized mounted trees with the existing depth-16 and 10000-entry bounds and cancellation checks. It SHALL retain a valid current pair, otherwise restore the same volume's explicitly chosen pair only if still discovered and authorized, otherwise select a single valid pair. Multiple pairs without a valid remembered choice SHALL remain unselected. Only source-selection metadata SHALL be persisted privately; genetic data, reads, results and API payloads SHALL NOT be persisted by this feature.

#### Scenario: Remembered source restored
- **WHEN** the same authorized USB is reinserted and its remembered pair remains discoverable
- **THEN** the pair SHALL be restored without another system picker; a missing or revoked source SHALL NOT be restored from metadata alone.

##### Example: Multiple pairs and a remembered choice
- **GIVEN** USB UUID ABCD-1234 has authorized pairs gene1 and gene2 and the stored explicit choice is gene2
- **WHEN** discovery runs after reinsertion
- **THEN** gene2 SHALL be selected; if gene2 disappears and gene1 plus gene3 remain, selection SHALL be empty rather than guessing.

#### Scenario: Root initial location requires user grant
- **WHEN** the user requests authorization for mounted USB UUID ABCD-1234
- **THEN** the picker SHALL target document ID ABCD-1234: at the USB root and require user confirmation; cancellation SHALL leave authorization unchanged and SHALL NOT start computation.

### Requirement: Dismissible USB insertion confirmation
The chat room SHALL automatically display one dismissible confirmation dialog for newly mounted USB volume identities, including a USB already present at first entry. Close, cancel, Android back and outside taps SHALL dismiss it without starting C, HTTP or a system picker. Repeated refreshes, panel loading and returning from the permission picker SHALL NOT reopen a dismissed dialog for the same attachment. Tapping the USB icon SHALL reopen it; the settings arrow SHALL retain upper-panel controls. The dialog SHALL present readable USB/source labels, root-scope defaults and actual authorization scope, explicit volume/source choices when ambiguous, a user-initiated system authorization action and an explicit use-source confirmation. Chat submission SHALL require a confirmed current authorized source and ready set; dismissal SHALL block submission without cloud/BLE fallback while USB remains present. Source changes, removal and logout SHALL invalidate confirmation; stale callbacks SHALL NOT restore it. Dialogs SHALL be bounded and scrollable with the keyboard open, SHALL be cleaned up on removal/disposal/logout, and SHALL NOT mutate sources during a busy job. Only a subsequent valid chat send SHALL run the unchanged C locus workflow.

#### Scenario: Dismiss and reopen
- **WHEN** the user closes insertion confirmation and discovery refreshes
- **THEN** no dialog SHALL automatically reopen, no job SHALL run, and the USB icon SHALL remain available for reopening confirmation.

##### Example: Confirm before computation
- **GIVEN** mounted authorized USB usb1 with readable folder USB / gene and the ready alcohol set
- **WHEN** the user dismisses the initial dialog, reopens it from the icon and confirms that source
- **THEN** runCalls SHALL remain zero until the user sends chat text, at which point C SHALL receive 143 references for 77 grouped loci.

#### Scenario: Removal during confirmation
- **WHEN** USB is removed while confirmation or authorization is pending
- **THEN** the dialog SHALL close, selection and confirmation SHALL become invalid, and a late permission callback SHALL NOT confirm the removed attachment or start computation.

### Requirement: Direct USB source access
The Android app SHALL read combined_idx_all.txt and combined_ids_all.txt directly and read-only from the same authorized mounted removable USB folder, without full-file copying or selecting primary phone storage. It SHALL validate file sizes and 64-bit seek support and require explicit selection when multiple pairs exist.

#### Scenario: Large source selected
- **WHEN** a USB pair has a 512 MiB IDX and a valid IDs larger than 4 GiB
- **THEN** the app SHALL validate random access without importing the pair into private phone storage.

#### Scenario: Unusable source
- **WHEN** permission is missing, the source is internal phone storage, or the descriptor is not seekable
- **THEN** the app SHALL reject the source with an explicit error and SHALL NOT request write access as a workaround.

### Requirement: Bounded native SNP counting
A C engine SHALL decode the existing little-endian K=13 IDX/IDs format with 64-bit offsets, validate posting ranges, and count each qualifying read once per locus across orientations. It SHALL retain distinct REF, ALT, ambiguous and coverage-only counts, report skipped high-frequency buckets, and fail rather than truncate at the candidate limit.

#### Scenario: Evidence partition
- **WHEN** valid queries match duplicated IDs or both orientations
- **THEN** duplicates SHALL NOT increase independent read depth and total SHALL equal REF plus ALT plus ambiguous plus coverage-only.

##### Example: Ambiguous evidence
- **GIVEN** one qualifying read with equal nonzero REF and ALT support
- **WHEN** the read is classified
- **THEN** total=1, REF=0, ALT=0, ambiguous=1, coverageOnly=0.

#### Scenario: Invalid data
- **WHEN** a posting extends beyond IDs length, reads fail, or candidate count exceeds one million
- **THEN** the engine SHALL return a structured error and SHALL NOT produce a successful genotype.

### Requirement: Independent beta-binomial genotyping
A separate C model SHALL compute normalized posterior probabilities for diploid biallelic 0/0, 0/1 and 1/1 using effectiveDepth=REF+ALT and versioned validated parameters. It SHALL NOT use the demo threshold caller, PairHMM, fabricated base qualities, or a GATK-equivalence claim. Research defaults SHALL be epsilon=0.01, rho=0.02, equal genotype priors, minDepth=10 and minPosterior=0.99; invalid parameters SHALL fail explicitly.

#### Scenario: Insufficient evidence
- **WHEN** effective depth is below the configured minimum, posterior is below its minimum, or highest posterior is tied
- **THEN** GT SHALL be ./. with a no-call reason.

##### Example: Excluded reads
- **GIVEN** REF=4, ALT=4, ambiguous=50 and coverageOnly=50 with research defaults
- **WHEN** genotyping runs
- **THEN** effectiveDepth=8 and GT=./. for insufficient depth.

#### Scenario: Calibrated status
- **WHEN** results use research defaults
- **THEN** results SHALL include modelVersion=bb-research-v1, calibrated=false, all three posterior values and the parameter configuration.

### Requirement: Independent Flutter compute workflow
Flutter SHALL expose an Android-only computation page supporting a single 301 bp A/C/G/T query or a validated FASTA panel of at most 3000 loci, REF/ALT definitions, progress, cancellation, counts and no-call results. USB import and AI URL API SHALL remain separate features. The page SHALL display an uncalibrated research-model warning.

#### Scenario: Responsive computation
- **WHEN** a user starts a valid query against the selected USB pair
- **THEN** computation SHALL run off the UI thread and SHALL publish job-scoped progress and results.

#### Scenario: Cancelled or stale results
- **WHEN** cancellation, USB removal, source change or plugin detach occurs
- **THEN** the job SHALL stop and stale results SHALL NOT become successful current results.

#### Scenario: Invalid query
- **WHEN** a query has an invalid length, non-ACGT bases, equal REF/ALT, invalid center allele, malformed FASTA or duplicate locus identifiers
- **THEN** the app SHALL reject the input without starting partial computation.

### Requirement: Opt-in debug results and stage timing
The SNP page SHALL offer a debug mode that defaults to disabled and is fixed for each running job. Enabled jobs SHALL expose selectable and explicitly copyable structured results, per-locus stage timings, and batch stage timings in milliseconds using monotonic elapsed time. Native I/O SHALL be measured around actual metadata/read system calls and SHALL be excluded from pure SNP counting time. Genotyping SHALL remain a separate C stage. Debug mode SHALL NOT change counts, posterior probabilities, or genotype decisions.

#### Scenario: Complete timing breakdown
- **WHEN** a debug-enabled USB computation completes
- **THEN** each locus SHALL expose ioMs, countMs, genotypeMs, nativeOverheadMs and nativeTotalMs; the batch SHALL expose setupIoMs, queryIoMs, countMs, genotypeMs, overheadMs and totalMs. All values SHALL be finite and nonnegative. Per-locus and batch totals SHALL equal their non-overlapping stages within 0.01 ms; batch query I/O, counting and genotyping SHALL equal the corresponding per-locus sums. The UI SHALL identify elapsed time rather than CPU time and explain that I/O includes provider/cache behavior.

##### Example: Non-overlapping elapsed time
- **GIVEN** one locus with native query elapsed time 12 ms including 7 ms I/O, 2 ms genotyping and 1 ms native overhead, plus 3 ms source setup and 4 ms additional batch overhead
- **WHEN** the debug report is generated
- **THEN** the locus SHALL report ioMs=7, countMs=5, genotypeMs=2, nativeOverheadMs=1 and nativeTotalMs=15; the batch SHALL report setupIoMs=3, queryIoMs=7, countMs=5, genotypeMs=2, overheadMs=5 and totalMs=22.

#### Scenario: Defined job timing boundary
- **WHEN** a batch reports totalMs
- **THEN** it SHALL measure from worker execution start through completed result construction, including source setup and result processing but excluding queue wait, Flutter rendering, copying and log output. Disabled debug jobs SHALL skip per-read clock instrumentation and SHALL omit debugTiming and debug-result logging.

#### Scenario: Safe result printing
- **WHEN** debug mode is enabled
- **THEN** a schemaVersion=1 report and GeneEdgeSnp logcat summaries SHALL contain counts, allele definitions, GT, posterior, no-call reason, model configuration and stage times, but SHALL NOT contain query sequences, raw read IDs, source URIs or file contents. The UI SHALL warn that aggregate genetic results remain sensitive. Clipboard writes SHALL require an explicit copy action; no automatic persistence or upload SHALL occur. Each log line SHALL be bounded to 3000 UTF-8 bytes and locus identifiers SHALL be escaped and truncated when necessary.

#### Scenario: Invalid or interrupted timing
- **WHEN** timing contains negative/nonfinite values or inconsistent stage sums
- **THEN** Flutter SHALL reject the payload with INVALID_FORMAT rather than displaying misleading times.
- **WHEN** cancellation, failure, USB removal or source invalidation interrupts a debug job
- **THEN** the app SHALL clear copyable successful reports, SHALL NOT label partial results as complete, and SHALL report only measured elapsedMs with the terminal status instead of a fabricated complete stage breakdown; stale events SHALL NOT restore a report.

### Requirement: Topic SNP set selection and bundled alcohol panel
The computation page SHALL use a topic-based SNP set selector as its primary input, preselecting Alcohol metabolism with 77 distinct loci and 143 allele-specific queries. The app SHALL bundle the unmodified alcohol.set143.k150.fasta reference asset with SHA-256 0bc77278d47ddcf41f1bbf4ef6f879d47f86c2d06791c0e29c5c0812a72b73f9 and version alcohol-set143-k150-v1, without bundling personal combined files. Full FASTA headers including REF and ALT SHALL identify bundled queries uniquely. Each query SHALL use the existing independent biallelic model, SHALL NOT be presented as a joint multiallelic genotype, and the UI SHALL disclose this limitation. Other existing chat topics without a defined SNP dataset SHALL be labeled unavailable and SHALL NOT be executable. Single-query and external FASTA inputs SHALL remain available as advanced modes.

#### Scenario: Automatic alcohol query loading
- **WHEN** the alcohol set is selected
- **THEN** the app SHALL automatically load and validate exactly 143 unique 301 bp queries, preserving their order, locus identifiers and REF/ALT definitions. The UI SHALL display the set name, version and validated count without requiring pasted sequences or a USB reference FASTA.

##### Example: Preserved locus identity
- **GIVEN** a bundled header rs1229984_4_100239319_T_C
- **WHEN** the panel is parsed
- **THEN** the bundled query SHALL retain id=rs1229984_4_100239319_T_C, REF=T and ALT=C, and the original 301 bp sequence; T_A and T_G queries at the same locus SHALL remain separate, without adding their counts together.

#### Scenario: Unavailable or invalid panel
- **WHEN** asset loading fails or the alcohol panel fails hash, count, uniqueness, allele or sequence validation
- **THEN** the page SHALL display a load error and SHALL disable run without silently substituting another input.
- **WHEN** the selected USB source is absent or panel loading is unfinished
- **THEN** run SHALL be disabled. Selection and input-mode changes SHALL be disabled during a running job.

#### Scenario: Set-scoped results
- **WHEN** a job starts using a selected set
- **THEN** the job SHALL capture set ID, label and version alongside its exact validated query list; completed results and debug reports SHALL display that captured set identity.
- **WHEN** the user changes the set or input mode while idle
- **THEN** old results and copyable reports SHALL be cleared, and stale asset loads or job events SHALL NOT relabel or restore them.

### Requirement: End-to-end offline alcohol workflow verification
Verification SHALL cover set selection, asset validation, direct USB access, C counting, independent C genotyping and result/debug presentation through the pre-LLM boundary. The offline workflow SHALL NOT automatically send HTTP requests or genetic results to the AI API. Automated fake-platform workflow tests SHALL be distinguished from native fixture tests and physical Pixel/USB validation.

#### Scenario: Complete alcohol panel job
- **WHEN** a valid alcohol panel is run against an authorized USB pair and all loci complete
- **THEN** progress SHALL reach 143/143 and results SHALL contain exactly the 143 requested allele-specific queries across 77 loci with their original alleles, counts, posterior and GT/no-call; enabled debug reports SHALL include per-query and batch timings and the captured alcohol set version.

#### Scenario: Honest physical validation
- **WHEN** tests run without the physical Pixel and USB or without known genotype truth
- **THEN** documentation SHALL NOT claim successful physical verification or biologically correct genotypes. Cancelled or failed batches SHALL NOT be reported as completed alcohol panel runs.

### Requirement: Joint locus evidence and statistical genotyping
A separate C locus engine SHALL validate common REF and identical normalized flanks for each rsID/chromosome/position group and jointly classify reads against all four central bases. It SHALL deduplicate each read across allele queries and orientations, assign unique positive maximum support to one base, classify ties as ambiguous and zero support as coverage-only, and retain the existing coverage threshold, bounded candidates, read-only access and cancellation behavior. It SHALL NOT add aggregate biallelic counts or multiply correlated per-query posteriors. A C Dirichlet-multinomial model SHALL compare all ten unordered diploid genotypes using mutually exclusive A/C/G/T counts, normalized posterior and maximum-posterior selection. Model version SHALL be dm-locus-research-v1 with calibrated=false, epsilon=0.01, rho=0.02, equal ten-genotype priors, minDepth=10 and minPosterior=0.99. The model SHALL use mu_b=d_b*(1-epsilon)+(1-d_b)*epsilon/3 and alpha_b=mu_b*(1/rho-1), where dosage d_b is 0, 0.5 or 1. It SHALL disclose uncalibrated error assumptions without fabricated base qualities or GATK-equivalence claims.

#### Scenario: One evidence observation per read
- **WHEN** the same read occurs in REF and several ALT queries or both orientations
- **THEN** it SHALL contribute at most once to total at that locus; total SHALL equal the four base counts plus ambiguous plus coverageOnly, and effectiveDepth SHALL equal only the four base counts. Invalid common flanks or REF SHALL fail the batch with INVALID_QUERY.

#### Scenario: Model-selected locus result
- **WHEN** a valid locus is evaluated
- **THEN** C SHALL return one locus result with ordered alleles, ten candidate posteriors, best candidate, actual-base genotype, best posterior, best-versus-runner-up log-score difference, counts, configuration and no-call reason. Zero/low depth, posterior below threshold or best log scores tied within 1e-12 SHALL produce no-call instead of an arbitrary first-query choice; invalid parameters or nonfinite calculations SHALL fail explicitly.

##### Example: Alternate-versus-alternate genotype
- **GIVEN** counts A=0, C=100, G=100, T=0 with research defaults
- **WHEN** the joint model evaluates the locus
- **THEN** the unordered C/G candidate SHALL have the highest posterior; output SHALL contain one locus rather than separate contradictory REF/C and REF/G genotypes.

### Requirement: Chat-integrated offline USB computation
The existing chat room SHALL expose an explicit USB-offline SNP mode without requiring navigation to a separate page. USB insertion SHALL expose source discovery and authorization status but SHALL NOT automatically start computation or upload data. In offline mode, sending user text SHALL snapshot the text, current topic's defined set, selected USB source and debug flag and run C locus computation instead of the cloud/BLE chat route. Ordinary chat SHALL retain its existing behavior. Busy jobs SHALL lock topic/mode/debug changes; unsupported topics and missing source or unfinished/invalid panel SHALL disable offline submission. Inline cards SHALL show source, set, progress, cancellation, locus results, research warning and opt-in stage timing. Cards SHALL remain ephemeral and SHALL NOT be persisted into chat history or automatically sent to TTS.

#### Scenario: Alcohol computation in the chat room
- **WHEN** the user selects alcohol, authorizes a USB pair and sends text in offline mode
- **THEN** the app SHALL validate the unchanged 143-reference panel and run 77 grouped loci, showing progress through 77/77 and a result/JSON card in the same chat room without HTTP or LLM calls. Debug SHALL preserve actual per-locus and batch I/O/count/model/overhead timings rather than summing overlapping legacy timings.

#### Scenario: Invalidated chat results
- **WHEN** a job is cancelled, fails, USB is removed, source/topic changes or logout occurs
- **THEN** its successful result card and copyable API payload SHALL be invalidated, partial results SHALL NOT be exported, and stale events SHALL NOT restore them. Unsupported topics SHALL NOT silently reuse the alcohol set.

### Requirement: Unique-locus API JSON export
Completed chat jobs SHALL expose explicitly copyable JSON independent of debug mode. API request fields SHALL match the existing askLlm contract: user_id, query, topic, SNP_list, snp_list, variants, variant_input_count, variant_used_count, no_call_count and yuguard. The three variant lists SHALL be identical, contain at most one rsID-actualBaseGenotype per locus and exclude no-calls. Input count SHALL use loci rather than reference-query records; yuguard SHALL be null without actual measurements. Allele ordering SHALL be REF first followed by remaining bases in A/C/G/T order. Duplicate rsIDs across distinct coordinates SHALL reject export. A separate schemaVersion=2 diagnostic envelope SHALL retain locus posteriors, no-calls, counts, job/set/model metadata and enabled timing; it SHALL NOT be confused with the API request or include sequences, raw read IDs or source URIs. No automatic network transmission, persistence or clipboard write SHALL occur.

#### Scenario: Actual-base genotype conversion
- **WHEN** a completed locus with REF=T and ALT=C is called as allele indices 0/1
- **THEN** the API variant SHALL be rsID-TC, not rsID-0/1 or an allele-qualified query ID. A no-call at that locus SHALL remain in diagnostic results but SHALL be absent from all three API variant lists.

#### Scenario: Complete export with no-calls
- **WHEN** an alcohol job completes all 77 loci with 70 calls and seven no-calls
- **THEN** each variant list SHALL contain 70 unique entries, variant_input_count SHALL equal 77, variant_used_count SHALL equal 70 and no_call_count SHALL equal seven; query/topic/user identity SHALL come from the job snapshot and the export SHALL cause no HTTP request.

### Requirement: USB-source chat message flow
The chat room SHALL treat an inserted removable USB as the source for phone-side C computation, analogous to the existing send-compute-result interaction for BLE, without an additional offline-mode switch or replacing the chat message list. USB insertion SHALL expose source readiness and authorization but SHALL NOT start a job. Existing chat bubbles and the composer SHALL remain visible. Sending text against a ready selected USB and valid topic set SHALL snapshot the text, topic, set, source and debug flag, execute runLoci, and append the latest ephemeral user bubble and assistant progress/result card to the same visible message stream. The card SHALL expose 77 grouped alcohol locus results, no-calls, opt-in stage timing and API JSON. Only the latest USB job pair SHALL be retained in memory. This path SHALL NOT invoke HTTP, BLE computation, Local JSON mock computation, automatic TTS or chat-history persistence.

#### Scenario: Send computes without a mode switch
- **WHEN** an authorized selected USB is present, alcohol is selected and the user sends a message
- **THEN** the app SHALL retain prior visible chat messages and show the sent text and computation progress/result in that same message list without an offline switch or page navigation.

##### Example: Alcohol chat computation
- **GIVEN** existing chat text "上一則對話", selected source usb1 and the valid 143-reference alcohol panel
- **WHEN** the user sends "我能喝酒嗎"
- **THEN** C SHALL receive the 143 references in locus mode, progress SHALL reach 77/77, "上一則對話" and the ephemeral sent text SHALL remain visible, and a unique-locus API JSON card SHALL appear without HTTP or persistence.

#### Scenario: USB readiness blocks unsafe fallback
- **WHEN** USB is present but authorization is missing, multiple pairs lack a selection, or the topic set is unsupported, loading or invalid
- **THEN** submission SHALL be disabled or explicitly rejected with the corresponding readiness state, without silently invoking BLE, Local JSON or cloud routes or substituting the alcohol set.

#### Scenario: Source lifetime and ordinary chat
- **WHEN** no USB is present and no USB job is pending
- **THEN** the original ordinary/BLE/Local JSON chat route SHALL remain available.
- **WHEN** a USB job is running
- **THEN** repeated send, topic/source and debug changes SHALL be locked; cancellation, unplugging, source/topic changes or logout SHALL invalidate its export and late events SHALL NOT restore it or reroute that message to the network.

### Requirement: USB detection icon and folder tooltip
The existing upper collapsible chat-settings panel SHALL display a USB icon in its header when removable USB volumes or sources are detected and SHALL hide it when no USB remains. The icon SHALL remain visible while the panel is collapsed. USB authorization, source selection, set information and debug controls SHALL be integrated into this existing upper dropdown rather than a separate AppBar entry, bottom sheet or permanent source-settings card in the message list. Chat bubbles and the composer SHALL remain intact. A selected authorized source with a valid ready set SHALL be distinguished from pending authorization, unselected multiple sources or an unready set through text and visual state. Mouse hover and touch long-press SHALL expose a Tooltip containing the selected source's readable label as the folder name, never its sourceId or SAF URI. Without a selection, the tooltip SHALL identify pending authorization or folder selection instead of guessing a source. Tapping the icon or the existing settings button SHALL expand the upper panel; its live source controls SHALL have bounded scrollable height and SHALL NOT overflow with the mobile keyboard open. Busy jobs SHALL disable mutation controls. Insertion, hover, long-press and expanding settings SHALL NOT start computation or networking. Only sending valid chat text with ready USB and set SHALL run C locus computation in the same chat message stream.

#### Scenario: Selected folder tooltip
- **WHEN** a detected USB has a selected source and the user hovers or long-presses the USB icon
- **THEN** the tooltip SHALL display the selected readable folder label and current readiness, without replacing the conversation or starting a job.

##### Example: Hover before chat send
- **GIVEN** source usb1 has label "USB / gene" and the alcohol set is ready
- **WHEN** the user hovers or long-presses the USB icon and opens its settings
- **THEN** the folder tooltip SHALL contain "USB / gene", exclude "usb1", and runCalls SHALL remain zero until the user sends text.

#### Scenario: Pending selection and removal
- **WHEN** multiple sources are detected without a selection or authorization is pending
- **THEN** the icon SHALL show a pending text state, submission SHALL remain blocked and no folder SHALL be presented as selected.
- **WHEN** the selected source is invalidated or USB is removed
- **THEN** the old folder tooltip SHALL be cleared; after discovery confirms no USB, the icon SHALL disappear and stale events SHALL NOT restore old results.
