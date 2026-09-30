## ADDED Requirements

The independent query-page and 143-query requirements below SHALL remain the legacy/advanced workflow. The added chat workflow SHALL use the separate joint-locus mode defined below, with 77 locus results derived from the unchanged 143-record reference panel. Legacy per-query results SHALL NOT substitute for joint-locus evidence or API export.

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
