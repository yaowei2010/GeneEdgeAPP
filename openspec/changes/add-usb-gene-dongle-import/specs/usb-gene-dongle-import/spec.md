## ADDED Requirements

### Requirement: Android detection and persisted read authorization

The Android app SHALL enumerate mounted non-primary removable volumes at startup, on foreground resume and on mount/eject/removal events. It SHALL request user authorization through SAF and persist read access only for external storage trees belonging to a currently mounted removable volume. It SHALL NOT hardcode a mount path or request all-files access. Other platforms SHALL report unsupported.

#### Scenario: Previously authorized dongle reconnects
- **WHEN** an authorized removable volume is mounted while the chat is open
- **THEN** the app automatically scans the authorized tree without another folder picker

#### Scenario: New dongle requires permission
- **WHEN** a mounted removable volume has no persisted read grant
- **THEN** the app reports permission_required and exposes a folder authorization action

#### Scenario: Internal folder or cancelled selection
- **WHEN** the selected tree belongs to primary storage or the user cancels
- **THEN** the app reports invalid_source or permission_denied and does not import data

### Requirement: Same-directory complete pair discovery

The importer SHALL search authorized trees for exact filenames combined_ids_all.txt and combined_idx_all.txt in the same directory. It SHALL report missing_files for no pair and ambiguous for multiple pairs. It SHALL fail with scan_limit if traversal exceeds 10000 entries or 16 child-directory levels instead of publishing partial discovery.

#### Scenario: Pair in a nested directory
- **WHEN** the only complete pair is in a nested directory within the authorized tree
- **THEN** the importer discovers both files and records that directory as the source

##### Example: Pairing boundaries
| Tree | Result |
| --- | --- |
| root/dongle/combined_ids_all.txt and root/dongle/combined_idx_all.txt | one pair |
| root/a/combined_ids_all.txt and root/b/combined_idx_all.txt | missing_files |
| complete pair under root/a and complete pair under root/b | ambiguous |

### Requirement: Transactional bounded raw file import

The importer SHALL stream both files unchanged to app-private no-backup storage before declaring ready. Each file MUST be non-empty and at most 256 MiB based on actual bytes read. Failed, cancelled or disconnected imports SHALL remove their partial output and preserve the previous successful dataset. It SHALL NOT parse the file format, compute results or send file contents to the network.

#### Scenario: Successful import survives USB removal
- **WHEN** both files are fully read and the USB is then removed
- **THEN** the saved dataset remains available as last-import metadata and the connection state becomes no_device

#### Scenario: Second file fails
- **WHEN** the first file copies but reading the second fails
- **THEN** the app reports io_failed, cleans the incomplete dataset and retains the previous successful dataset

#### Scenario: Empty or oversized file
- **WHEN** a file is empty or exceeds 256 MiB of actual read bytes
- **THEN** the importer reports empty_file or file_too_large without publishing the dataset

### Requirement: Isolated observable import lifecycle

The app SHALL provide an Android-only USB / Gene dongle page independent of chat, offline computation and AI API. It SHALL show connection/import state, device label, source URI and byte counts, with authorization and refresh actions. Snapshot revisions SHALL increase; older asynchronous results MUST NOT overwrite newer state. IO SHALL run off the Android main thread and detached listeners MUST NOT receive updates.

#### Scenario: User views the imported pair
- **WHEN** the import completes and the user opens USB / Gene dongle
- **THEN** both fixed filenames, byte counts and source URI are shown without a calculation or API request

#### Scenario: Stale result arrives
- **WHEN** snapshot revision 5 arrives after revision 6
- **THEN** revision 6 remains visible
