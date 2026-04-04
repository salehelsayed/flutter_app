# 42 — mknoon-backup Desktop Binary — TDD Plan

## Overview

A standalone Go binary (`mknoon-backup`) that runs on Windows/macOS/Linux.
Provides: pairing with phone, receiving encrypted backups over WiFi,
storing backup snapshots, and serving restore to a new phone via QR code.

**No Flutter. No mobile SDKs. Pure Go + embedded web UI.**

---

## Architecture

```
mknoon-backup/
├── main.go                # CLI entry: flags, start mDNS + HTTP
├── cmd/
│   └── root.go            # cobra or plain flag parsing
├── crypto/
│   ├── kdf.go             # Argon2id key derivation from passphrase
│   ├── kdf_test.go
│   ├── aead.go            # AES-256-GCM encrypt/decrypt (streaming)
│   ├── aead_test.go
│   ├── session.go         # pairing session key exchange (X25519 + HKDF)
│   └── session_test.go
├── discovery/
│   ├── mdns.go            # mDNS advertise _mknoon-backup._tcp
│   └── mdns_test.go
├── storage/
│   ├── snapshot.go         # backup snapshot CRUD (write, list, prune)
│   ├── snapshot_test.go
│   ├── manifest.go         # backup manifest (file list + checksums)
│   ├── manifest_test.go
│   ├── pairing.go          # persist pairing state to disk
│   └── pairing_test.go
├── server/
│   ├── server.go           # HTTP router (API + static web)
│   ├── server_test.go
│   ├── handler_pair.go     # POST /api/pair — pairing handshake
│   ├── handler_pair_test.go
│   ├── handler_backup.go   # POST /api/backup — receive backup push
│   ├── handler_backup_test.go
│   ├── handler_restore.go  # GET /api/restore — serve backup to phone
│   ├── handler_restore_test.go
│   ├── handler_status.go   # GET /api/status — JSON status
│   ├── handler_status_test.go
│   ├── middleware.go        # auth middleware (pairing token validation)
│   └── middleware_test.go
├── transfer/
│   ├── protocol.go         # chunked transfer framing over HTTP
│   ├── protocol_test.go
│   ├── incremental.go      # delta diffing (what's new since last backup)
│   └── incremental_test.go
├── web/                    # embedded via go:embed
│   ├── index.html          # status dashboard
│   ├── pair.html           # pairing QR + status
│   ├── restore.html        # restore QR + progress
│   ├── style.css
│   └── app.js
├── go.mod
└── go.sum
```

---

## Session 1 — Crypto Layer

### 1A. Key Derivation (kdf.go)

Argon2id from user passphrase → 256-bit symmetric key.

**Tests (kdf_test.go):**

```
TestDeriveKey_Deterministic
  Given same passphrase + salt
  When DeriveKey called twice
  Then both outputs are identical 32 bytes

TestDeriveKey_DifferentPassphrase_DifferentKey
  Given two different passphrases, same salt
  When DeriveKey called for each
  Then outputs differ

TestDeriveKey_DifferentSalt_DifferentKey
  Given same passphrase, two different salts
  When DeriveKey called for each
  Then outputs differ

TestDeriveKey_OutputLength
  When DeriveKey called
  Then result is exactly 32 bytes

TestDeriveKey_EmptyPassphrase_ReturnsError
  Given empty passphrase
  When DeriveKey called
  Then returns error

TestGenerateSalt_Uniqueness
  When GenerateSalt called twice
  Then results differ (random)

TestGenerateSalt_Length
  When GenerateSalt called
  Then result is exactly 16 bytes
```

**Implementation:**
- `DeriveKey(passphrase string, salt []byte) ([]byte, error)`
- `GenerateSalt() ([]byte, error)`
- Argon2id params: time=3, memory=64MB, threads=4, keyLen=32

---

### 1B. Authenticated Encryption (aead.go)

AES-256-GCM for encrypting backup chunks.

**Tests (aead_test.go):**

```
TestEncryptDecrypt_Roundtrip
  Given 32-byte key and plaintext "hello backup"
  When Encrypt then Decrypt
  Then recovered plaintext matches original

TestEncryptDecrypt_LargePayload
  Given 10 MB random payload
  When Encrypt then Decrypt
  Then recovered plaintext matches original

TestDecrypt_WrongKey_Fails
  Given ciphertext encrypted with key A
  When Decrypt with key B
  Then returns authentication error

TestDecrypt_TamperedCiphertext_Fails
  Given valid ciphertext, flip one byte
  When Decrypt
  Then returns authentication error

TestEncrypt_DifferentNonce_EachCall
  Given same key + plaintext
  When Encrypt called twice
  Then ciphertexts differ (random nonce)

TestEncryptStream_DecryptStream_Roundtrip
  Given a 50 MB byte reader
  When EncryptStream → write to buffer → DecryptStream → read
  Then all bytes match original
  (streaming for large media files)

TestEncryptStream_ChunkBoundaries
  Given payload size not aligned to chunk size
  When EncryptStream then DecryptStream
  Then roundtrip succeeds (last partial chunk handled)
```

**Implementation:**
- `Encrypt(key, plaintext []byte) ([]byte, error)` — prepends random 12-byte nonce
- `Decrypt(key, ciphertext []byte) ([]byte, error)` — splits nonce + GCM open
- `EncryptStream(key []byte, r io.Reader, w io.Writer) error` — 1 MB chunks, each chunk: `[4-byte len][nonce][ciphertext]`
- `DecryptStream(key []byte, r io.Reader, w io.Writer) error`

---

### 1C. Pairing Session (session.go)

Mutual key agreement for pairing: phone and laptop derive a shared secret
from the user's passphrase plus an ephemeral session exchange.

**Tests (session_test.go):**

```
TestNewPairingSession_GeneratesEphemeralKey
  When NewPairingSession()
  Then session has non-nil public key (32 bytes)

TestCompletePairing_SharedSecretMatches
  Given two sessions (phone + laptop)
  When each calls Complete with the other's public key + same passphrase
  Then both derive the same shared secret

TestCompletePairing_DifferentPassphrase_DifferentSecret
  Given two sessions
  When Complete with different passphrases
  Then shared secrets differ

TestPairingPayload_Serialize_Deserialize
  Given a PairingPayload{ip, port, sessionPubKey, deviceName}
  When JSON marshal/unmarshal
  Then fields roundtrip correctly

TestPairingPayload_ToQRData
  Given a PairingPayload
  When ToQRData() called
  Then returns valid JSON string ≤ 2048 bytes (QR capacity)
```

**Implementation:**
- `PairingSession` struct: ephemeral X25519 keypair
- `NewPairingSession() (*PairingSession, error)`
- `(s *PairingSession) Complete(remotePub []byte, passphrase string) (sharedKey []byte, error)`
  - X25519 ECDH → HKDF-SHA256(ikm=ecdh, salt=Argon2id(passphrase), info="mknoon-backup-pairing") → 32-byte key
- `PairingPayload` struct with JSON tags + `ToQRData()` helper

---

## Session 2 — Storage Layer

### 2A. Backup Manifest (manifest.go)

Tracks what files are in a backup snapshot + their checksums for incremental diffing.

**Tests (manifest_test.go):**

```
TestManifest_AddEntry
  When AddEntry("media/peer1/abc.jpg", sha256, size, modTime)
  Then Entries() contains exactly that entry

TestManifest_Serialize_Deserialize
  Given manifest with 3 entries
  When JSON marshal then unmarshal
  Then all entries roundtrip

TestManifest_Diff_NewFiles
  Given prev manifest with files [A, B]
  And curr manifest with files [A, B, C]
  When Diff(prev, curr)
  Then result.Added = [C], result.Removed = [], result.Changed = []

TestManifest_Diff_RemovedFiles
  Given prev [A, B, C], curr [A, B]
  When Diff(prev, curr)
  Then result.Removed = [C]

TestManifest_Diff_ChangedFiles
  Given prev has file A with hash X
  And curr has file A with hash Y
  When Diff(prev, curr)
  Then result.Changed = [A]

TestManifest_Diff_Empty
  Given identical manifests
  When Diff
  Then all lists empty

TestManifest_FromDirectory
  Given a temp dir with 3 files
  When ManifestFromDirectory(dir)
  Then manifest has 3 entries with correct sha256 and sizes
```

**Implementation:**
- `ManifestEntry{Path, SHA256, Size, ModTime}`
- `Manifest` struct with entries map
- `ManifestFromDirectory(dir string) (*Manifest, error)` — walks dir, hashes each file
- `Diff(prev, curr *Manifest) DiffResult`
- `DiffResult{Added, Removed, Changed []string}`

---

### 2B. Backup Snapshot (snapshot.go)

Stores encrypted backups on the laptop's filesystem.

**Tests (snapshot_test.go):**

```
TestWriteSnapshot_CreatesDirectory
  Given backupDir and snapshot data
  When WriteSnapshot(data, manifest)
  Then dir exists at backupDir/<timestamp>/

TestWriteSnapshot_WritesManifestFile
  When WriteSnapshot
  Then <timestamp>/manifest.json exists and is valid

TestWriteSnapshot_WritesAllFiles
  Given data with db.enc + secrets.enc + 2 media files
  When WriteSnapshot
  Then all 4 files exist in snapshot dir

TestListSnapshots_Empty
  Given empty backup dir
  When ListSnapshots()
  Then returns empty slice

TestListSnapshots_MultipleSorted
  Given 3 snapshots at different times
  When ListSnapshots()
  Then returns 3, newest first

TestLatestSnapshot
  Given 3 snapshots
  When LatestSnapshot()
  Then returns the newest one

TestPruneSnapshots_KeepsN
  Given 7 snapshots, maxKeep=5
  When PruneSnapshots(5)
  Then 2 oldest deleted, 5 remain

TestPruneSnapshots_NothingToDelete
  Given 3 snapshots, maxKeep=5
  When PruneSnapshots(5)
  Then all 3 remain

TestReadSnapshot_ReturnsContents
  Given a written snapshot
  When ReadSnapshot(snapshotID)
  Then returned data matches original

TestSnapshotPath_DefaultLocation
  When DefaultBackupDir()
  Then returns $HOME/.mknoon-backup/backups/ (macOS/Linux)
  Or returns %APPDATA%/mknoon-backup/backups/ (Windows)
```

**Implementation:**
- `WriteSnapshot(dir string, manifest *Manifest, files map[string]io.Reader) (snapshotID string, error)`
- `ListSnapshots(dir string) ([]SnapshotMeta, error)`
- `LatestSnapshot(dir string) (*SnapshotMeta, error)`
- `PruneSnapshots(dir string, keep int) error`
- `ReadSnapshotFile(dir, snapshotID, filePath string) (io.ReadCloser, error)`
- Default dir: `~/.mknoon-backup/` (macOS/Linux), `%APPDATA%\mknoon-backup\` (Windows)

---

### 2C. Pairing Persistence (pairing.go)

Save/load pairing state so the desktop app remembers paired phones across restarts.

**Tests (pairing_test.go):**

```
TestSavePairing_CreatesPairingFile
  Given a PairingState{phoneID, sharedKey, deviceName, pairedAt}
  When SavePairing(state)
  Then pairing.json exists in config dir

TestLoadPairing_Roundtrip
  Given saved pairing state
  When LoadPairing()
  Then all fields match

TestLoadPairing_NoPairingFile_ReturnsNil
  Given no pairing.json
  When LoadPairing()
  Then returns nil, no error

TestDeletePairing_RemovesFile
  Given saved pairing
  When DeletePairing()
  Then LoadPairing returns nil

TestIsPaired
  Given saved pairing
  When IsPaired()
  Then returns true

TestSavePairing_EncryptsSharedKey
  Given pairing state
  When SavePairing then read raw file
  Then sharedKey field is NOT plaintext (encrypted with machine-local key)
```

**Implementation:**
- `PairingState{PhoneID, SharedKey, DeviceName, PairedAt, LastBackup}`
- `SavePairing(dir string, state *PairingState) error`
- `LoadPairing(dir string) (*PairingState, error)`
- `DeletePairing(dir string) error`
- Shared key encrypted at rest using OS keyring or DPAPI (Windows) / Keychain (macOS) / libsecret (Linux)

---

## Session 3 — mDNS Discovery

### 3A. Service Advertisement (mdns.go)

Advertise `_mknoon-backup._tcp` so the phone can find the laptop.

**Tests (mdns_test.go):**

```
TestAdvertise_StartsWithoutError
  When Advertise(port=8470, deviceName="My MacBook")
  Then returns no error and cleanup func

TestAdvertise_Discoverable
  Given Advertise running on port 8470
  When mDNS browse for "_mknoon-backup._tcp"
  Then finds exactly one entry with correct port and TXT records

TestAdvertise_TXTRecords
  Given Advertise running
  When discovered
  Then TXT contains: deviceName, version, paired=true/false

TestAdvertise_Stop
  Given Advertise running
  When cleanup func called
  Then mDNS browse finds no entries

TestDiscover_FindsAdvertisedService
  Given a service advertising on _mknoon-backup._tcp
  When Discover(timeout=2s)
  Then returns at least one BackupService{IP, Port, DeviceName}

TestDiscover_Timeout_NoService
  Given no service advertising
  When Discover(timeout=1s)
  Then returns empty list, no error

TestDiscover_MultipleServices
  Given 2 services advertising
  When Discover(timeout=2s)
  Then returns 2 entries
```

**Implementation:**
- `Advertise(port int, deviceName string, paired bool) (stop func(), error)`
- `Discover(timeout time.Duration) ([]BackupService, error)`
- `BackupService{IP net.IP, Port int, DeviceName string, Paired bool}`
- Uses `github.com/grandcat/zeroconf` (pure Go, cross-platform mDNS/DNS-SD)

---

## Session 4 — HTTP Server + API

### 4A. Server Skeleton + Auth Middleware (server.go, middleware.go)

**Tests (server_test.go):**

```
TestServer_Starts
  When NewServer(port=0) and Start()
  Then server.Addr() returns a valid address

TestServer_ServesWebUI
  Given running server
  When GET /
  Then status 200, content-type text/html, body contains "mknoon"

TestServer_ServesStaticAssets
  When GET /style.css
  Then status 200, content-type text/css

TestServer_UnknownRoute_404
  When GET /nonexistent
  Then status 404
```

**Tests (middleware_test.go):**

```
TestAuthMiddleware_NoPairing_AllowsPairEndpoint
  Given no active pairing
  When POST /api/pair with valid session token
  Then request passes through (no auth required for pairing)

TestAuthMiddleware_NoPairing_BlocksBackupEndpoint
  Given no active pairing
  When POST /api/backup
  Then status 403 "not paired"

TestAuthMiddleware_ValidToken_Passes
  Given active pairing with known sharedKey
  When request with Authorization: Bearer HMAC(sharedKey, timestamp)
  Then request passes through

TestAuthMiddleware_InvalidToken_Rejects
  Given active pairing
  When request with bad Authorization header
  Then status 401

TestAuthMiddleware_ExpiredToken_Rejects
  Given valid token but timestamp > 5 min old
  When request
  Then status 401 "token expired"

TestAuthMiddleware_StatusEndpoint_NoAuthNeeded
  When GET /api/status (no auth header)
  Then status 200 (public endpoint — shows if paired or not)
```

**Implementation:**
- `Server` struct wrapping `http.Server` + router (`http.ServeMux`)
- `authMiddleware(pairingStore, next http.Handler) http.Handler`
- Token: `HMAC-SHA256(sharedKey, timestamp_rounded_to_30s)` — simple time-based auth
- Static files served via `go:embed web/*`

---

### 4B. Pairing Handler (handler_pair.go)

**Tests (handler_pair_test.go):**

```
TestPairHandler_GeneratesQRPayload
  Given server not yet paired
  When GET /api/pair/qr
  Then returns JSON {ip, port, sessionPubKey, deviceName}
  And all fields are valid

TestPairHandler_CompletePairing
  Given server returned QR payload
  When POST /api/pair/complete with {phonePubKey, phoneID, passphrase_proof}
  Then returns 200 {status: "paired"}
  And pairing state is persisted

TestPairHandler_CompletePairing_WrongProof_Rejects
  Given server returned QR payload
  When POST /api/pair/complete with invalid passphrase_proof
  Then returns 400 "pairing verification failed"

TestPairHandler_AlreadyPaired_RejectsDifferentPhone
  Given already paired with phone A
  When POST /api/pair/complete from phone B
  Then returns 409 "already paired — unpair first"

TestPairHandler_Unpair
  Given active pairing
  When POST /api/pair/unpair
  Then returns 200
  And pairing state is deleted

TestPairHandler_PairingStatus
  Given active pairing
  When GET /api/pair/status
  Then returns {paired: true, phoneID: "...", deviceName: "..."}
```

**Implementation:**
- `GET /api/pair/qr` → generate ephemeral X25519 keypair, return JSON for QR encoding
- `POST /api/pair/complete` → receive phone's ephemeral pub key + passphrase proof (HMAC of shared secret), derive shared key, save pairing
- `POST /api/pair/unpair` → delete pairing state
- `GET /api/pair/status` → return pairing state (public endpoint)

---

### 4C. Backup Handler (handler_backup.go)

Receives backup pushes from the phone.

**Tests (handler_backup_test.go):**

```
TestBackupHandler_ReceiveFullBackup
  Given paired and authenticated
  When POST /api/backup with multipart body:
    part "manifest" = manifest JSON
    part "secrets" = encrypted secrets bundle
    part "database" = encrypted DB file
    part "media/peer1/abc.jpg" = encrypted media file
  Then returns 200 {snapshotID: "..."}
  And snapshot directory contains all files

TestBackupHandler_ReceiveIncrementalBackup
  Given existing snapshot with files [A, B]
  When POST /api/backup with manifest adding [C] and changing [B]
  Then new snapshot contains [A(from prev), B(new), C(new)]

TestBackupHandler_NotPaired_Rejects
  When POST /api/backup without auth
  Then status 403

TestBackupHandler_InvalidManifest_Rejects
  When POST /api/backup with invalid manifest JSON
  Then status 400

TestBackupHandler_PrunesOldSnapshots
  Given 5 existing snapshots, maxKeep=5
  When POST /api/backup with new backup
  Then oldest snapshot deleted, 5 remain

TestBackupHandler_LargeMedia_StreamsWithoutOOM
  Given paired
  When POST /api/backup with a 500 MB media file
  Then memory usage stays under 50 MB (streaming, not buffered)
  And snapshot written correctly

TestBackupHandler_ReportsProgress
  Given paired, SSE connection open on GET /api/backup/progress
  When POST /api/backup with large payload
  Then SSE events report {bytesReceived, totalBytes, currentFile}

TestBackupHandler_ConcurrentBackup_Serialized
  Given backup in progress
  When second POST /api/backup arrives
  Then status 409 "backup in progress"

TestBackupHandler_DatabaseIntegrity
  Given received backup with encrypted DB
  When decrypt DB file with pairing key
  Then file is valid SQLite (starts with "SQLite format 3")
```

**Implementation:**
- `POST /api/backup` — multipart/form-data with streaming parts
- Each part written to temp dir, then atomically moved to snapshot dir
- Incremental: compare incoming manifest with latest snapshot's manifest, only receive changed/new files, hardlink unchanged files from previous snapshot
- Prune after successful write (keep last 5)
- `GET /api/backup/progress` — SSE stream for web UI progress display

---

### 4D. Restore Handler (handler_restore.go)

Serves backup to a new phone during recovery.

**Tests (handler_restore_test.go):**

```
TestRestoreHandler_GeneratesQRPayload
  Given paired and has snapshots
  When GET /api/restore/qr
  Then returns JSON {ip, port, sessionToken, snapshotID}
  And sessionToken is one-time-use

TestRestoreHandler_ServeRestoreManifest
  Given valid session token
  When GET /api/restore/manifest?token=...
  Then returns manifest JSON of latest snapshot

TestRestoreHandler_ServeRestoreFile
  Given valid session token
  When GET /api/restore/file?token=...&path=database.db.enc
  Then streams the encrypted file

TestRestoreHandler_ServeRestoreFile_MediaStreaming
  Given valid session token and snapshot with 200MB video
  When GET /api/restore/file?path=media/peer1/video.mp4.enc
  Then response streams without loading into memory

TestRestoreHandler_InvalidToken_Rejects
  When GET /api/restore/manifest?token=bad
  Then status 401

TestRestoreHandler_ExpiredToken_Rejects
  Given session token older than 15 minutes
  When GET /api/restore/manifest?token=...
  Then status 401 "session expired"

TestRestoreHandler_NoSnapshots_404
  Given paired but no snapshots yet
  When GET /api/restore/qr
  Then status 404 "no backups available"

TestRestoreHandler_CompletesRestore
  Given valid session + full download
  When POST /api/restore/complete?token=...
  Then session token invalidated
  And old pairing deleted (new phone will re-pair)
```

**Implementation:**
- `GET /api/restore/qr` → generate one-time session token, return QR JSON
- `GET /api/restore/manifest` → serve snapshot manifest
- `GET /api/restore/file?path=...` → stream individual file from snapshot
- `POST /api/restore/complete` → invalidate session, reset pairing
- Phone downloads manifest first, then fetches files one by one (resumeable)

---

### 4E. Status Handler (handler_status.go)

**Tests (handler_status_test.go):**

```
TestStatusHandler_NotPaired
  When GET /api/status
  Then {paired: false, lastBackup: null, snapshotCount: 0}

TestStatusHandler_PairedNoBackup
  Given paired, no backups
  When GET /api/status
  Then {paired: true, deviceName: "...", lastBackup: null, snapshotCount: 0}

TestStatusHandler_PairedWithBackups
  Given paired with 3 snapshots, latest at "2026-04-02T10:00:00Z"
  When GET /api/status
  Then {paired: true, lastBackup: "2026-04-02T10:00:00Z",
        snapshotCount: 3, totalSize: 142000000}
```

---

## Session 5 — Transfer Protocol

### 5A. Chunked Transfer (protocol.go)

Framing for large backup transfers over HTTP.

**Tests (protocol_test.go):**

```
TestChunkEncode_Decode_Roundtrip
  Given 5 MB of data, chunk size 1 MB
  When ChunkEncode → buffer → ChunkDecode
  Then all bytes match

TestChunkEncode_FinalChunkMarker
  Given data
  When ChunkEncode
  Then last chunk has isFinal=true

TestChunkDecode_TruncatedStream_Error
  Given encoded stream, truncate last 100 bytes
  When ChunkDecode
  Then returns "unexpected EOF" error

TestChunkEncode_EmptyData
  When ChunkEncode empty reader
  Then produces single final chunk with 0 data bytes
```

---

### 5B. Incremental Diff (incremental.go)

Determine what files need to be sent for an incremental backup.

**Tests (incremental_test.go):**

```
TestComputeIncremental_FirstBackup_AllFiles
  Given no previous manifest
  When ComputeIncremental(current manifest with 10 files)
  Then returns all 10 files as "send"

TestComputeIncremental_NoChanges_EmptyDiff
  Given prev = curr manifest (same hashes)
  When ComputeIncremental
  Then returns empty send list

TestComputeIncremental_NewMediaFile
  Given prev with [db, secrets, media/a.jpg]
  And curr adds media/b.jpg
  When ComputeIncremental
  Then send list = [db, secrets, media/b.jpg]
  (db and secrets always sent — they change with every message)

TestComputeIncremental_DatabaseAlwaysSent
  Given prev and curr with identical media
  When ComputeIncremental
  Then send list includes database (always) but not unchanged media

TestComputeIncremental_DeletedMediaFile
  Given prev has media/old.jpg, curr does not
  When ComputeIncremental
  Then removals list = [media/old.jpg]
```

**Implementation:**
- `ComputeIncremental(prev, curr *Manifest) IncrementalPlan`
- `IncrementalPlan{Send []string, Remove []string, LinkFromPrev []string}`
- DB + secrets always sent (they change frequently)
- Media compared by SHA-256

---

## Session 6 — Web UI (Embedded)

### 6A. Status Dashboard (index.html)

No Go tests — browser-tested manually + one integration test.

**Integration test:**

```
TestWebUI_StatusPage_RendersPairedState
  Given server running with pairing
  When fetch GET / with Accept: text/html
  Then body contains "Paired with" and device name

TestWebUI_StatusPage_ShowsLastBackupTime
  Given server with snapshot at "2026-04-02T10:00:00Z"
  When GET /
  Then body contains "10:00" or relative "2 hours ago"
```

**Content:**
- Pairing status: paired/not paired
- Last backup time + size
- Number of snapshots stored
- Link to "Pair new device" or "Unpair"
- Link to "Restore to new phone"

---

### 6B. Pair Page (pair.html)

**Integration test:**

```
TestWebUI_PairPage_ShowsQRCode
  Given server not paired
  When GET /pair.html
  Then page contains a QR code SVG/canvas
  And QR data decodes to valid pairing JSON

TestWebUI_PairPage_ShowsSuccessAfterPairing
  Given pairing completed via API
  When GET /pair.html (poll or SSE update)
  Then page shows "Paired successfully with <device>"
```

---

### 6C. Restore Page (restore.html)

**Integration test:**

```
TestWebUI_RestorePage_ShowsQR
  Given server paired with snapshots
  When GET /restore.html and click "Start restore"
  Then QR code displayed with restore session data

TestWebUI_RestorePage_ShowsProgress
  Given restore in progress
  When SSE updates arrive
  Then progress bar updates (files transferred / total)
```

---

## Session 7 — End-to-End Integration

### 7A. Full Pairing Flow (e2e_pair_test.go)

```
TestE2E_PairingFlow
  1. Start mknoon-backup server
  2. GET /api/pair/qr → parse QR payload
  3. Simulate phone: generate ephemeral key, POST /api/pair/complete
     with phone pub key + passphrase "test-pass-123"
  4. Assert server returns {status: "paired"}
  5. Assert pairing.json persisted to disk
  6. Restart server → assert still paired (persistence)
```

### 7B. Full Backup Flow (e2e_backup_test.go)

```
TestE2E_FullBackupAndRestore
  1. Start server, complete pairing (passphrase "test-pass-123")
  2. POST /api/backup with:
     - manifest: {database.db.enc, secrets.enc, media/p1/a.jpg.enc}
     - encrypted files (encrypt with derived key from passphrase)
  3. Assert GET /api/status shows lastBackup ≠ null
  4. GET /api/restore/qr → QR payload
  5. GET /api/restore/manifest → matches uploaded manifest
  6. GET /api/restore/file?path=database.db.enc → decrypt → valid SQLite header
  7. GET /api/restore/file?path=secrets.enc → decrypt → valid JSON with keys
  8. GET /api/restore/file?path=media/p1/a.jpg.enc → decrypt → matches original
  9. POST /api/restore/complete → session invalidated
```

### 7C. Incremental Backup Flow (e2e_incremental_test.go)

```
TestE2E_IncrementalBackup
  1. Pair + send full backup with [db, secrets, media/a.jpg]
  2. Assert snapshot 1 created with 3 files
  3. Send incremental backup with [db, secrets, media/a.jpg, media/b.jpg]
     (only db + secrets + b.jpg actually transferred)
  4. Assert snapshot 2 has 4 files (a.jpg hardlinked from snapshot 1)
  5. Assert transfer size < full backup size
```

### 7D. mDNS Discovery (e2e_mdns_test.go)

```
TestE2E_mDNS_DiscoverableOnLocalNetwork
  1. Start server with mDNS advertising
  2. From same machine: browse _mknoon-backup._tcp
  3. Assert found service with correct port + TXT records
  4. Stop server
  5. Browse again → not found
```

---

## Build & Distribution

- `go build -o mknoon-backup .` — single binary, all platforms
- `GOOS=darwin GOARCH=arm64 go build ...` (Apple Silicon)
- `GOOS=windows GOARCH=amd64 go build ...`
- `GOOS=linux GOARCH=amd64 go build ...`
- No installer needed — download and run
- Web UI auto-opens browser on first launch via `xdg-open` / `open` / `start`

---

## Dependency Choices

| Need | Package | Why |
|------|---------|-----|
| mDNS | `github.com/grandcat/zeroconf` | Pure Go, cross-platform, well-maintained |
| Argon2 | `golang.org/x/crypto/argon2` | Already in go-mknoon deps |
| AES-GCM | `crypto/aes` + `crypto/cipher` | stdlib |
| HKDF | `golang.org/x/crypto/hkdf` | Already in go-mknoon deps |
| X25519 | `golang.org/x/crypto/curve25519` | Already in go-mknoon deps |
| HTTP | `net/http` | stdlib |
| QR encode | `github.com/skip2/go-qrcode` | SVG output for web UI |
| Embed | `embed` | stdlib, Go 1.16+ |
