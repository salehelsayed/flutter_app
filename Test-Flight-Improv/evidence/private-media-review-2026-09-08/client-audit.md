# Private-media client audit — 2026-09-08

Read-only audit of the private-media policy/model, inbound decoder, outgoing serialization, logging, and available two-iPhone test setup. No incident cause is established by this audit. No application code, protection rule, device account, or message was changed.

## Scope and provenance

The reported incident concerns two iPhone-to-iPhone photos sent around 18:06 UTC, one Protected and one View Once, with both reported endpoints on 1.0.1(111). The receiver showed the update/unsupported copy. That copy alone does not identify a policy-version failure: the parent UI investigation also identified integrity failure and inconsistent lifecycle state as selectors of the original copy.

The source and tests below were reviewed in the current workspace. The eight policy/model/inbound/send/upload/retry files checked had no uncommitted diff against HEAD. Neither that observation nor the shared 1.0.1(111) version establishes a matching source commit or binary hash for the shipped incident endpoints. The current-source findings must not be presented as artifact-proven implementation details of that release.

## Policy and wire evidence

- `lib/core/media/private_media_policy.dart:160`: wire policy requires integer version 1 and a recognized mode. Invalid shape/version/mode/duration becomes unsupported. A protected/view-once policy with one eligible image and empty text is supported. Database decoding separately normalizes numeric version values (`:200`).
- `lib/features/conversation/domain/models/message_payload.dart:196`: the decrypted inner JSON is decoded in Dart; `:224` validates private policy against the original text and media before incoming text redaction. Nonempty text/caption, an edit/forward, or an ineligible media shape can invalidate the policy. `:257` serializes the policy inside the encrypted inner payload. Lifecycle state is receiver-owned and is intentionally absent from this wire format.
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart:249`: live decrypt and staged predecrypt both feed the plaintext string to the same decoder. `_decryptV2ChatEnvelope` at `:1585` takes the bridge's `plaintext` as a string. The independent native audit also confirmed opaque-string forwarding at `ios/Runner/GoBridge.swift:234` and `go-mknoon/bridge/bridge.go:185`; neither boundary parses and rewrites nested policy numbers.
- The same handler's strict-custody parser at `:1746` refuses malformed private custody payloads before persistence. A legacy payload without blob custody can instead persist an unsupported/redacted row. Lifecycle seeding at `:2063` preserves an existing private checkpoint, including unsupported or terminal state, across replay.
- `lib/features/conversation/domain/models/media_attachment.dart:249` initializes wire attachments with pending download status; `:173` restores the durable download status. These model decoders do not manufacture `integrity_failed`.

## Outgoing photo evidence

`send_chat_message_use_case.dart:1077` selects the supplied or durable retry policy; `:1142` rejects ineligible private text/media before encryption. At `:1722`, attachment normalization changes message ownership/identity timestamps, not size/hash/key material. At `:1916`, protected-photo thumbnail insertion adds an inner attachment field. At `:1934` and `:2061`, the actual encrypted message uses the validated text and `MessagePayload.toInnerJson()`.

No reviewed sender path substitutes the notification hint `Private media` into a valid private encrypted message. Nonempty private text is explicitly refused. `retry_failed_messages_use_case.dart:1165` passes the durable policy, text, and attachments back to the sender; absent wire lifecycle fields are intentional.

`upload_media_use_case.dart:184` prepares AES-GCM ciphertext and hashes that ciphertext. The upload at `:626` sends the encrypted file; the returned attachment at `:802` carries the plaintext size. `go-mknoon/crypto/file_crypto.go:26` and `go-mknoon/bridge/bridge_test.go:5356` establish the ciphertext-length convention of plaintext plus the 16-byte authentication tag. For the two relay ciphertext lengths supplied by the parent investigation, the expected attachment plaintext sizes are:

| Relay ciphertext bytes | Expected attachment.size |
|---:|---:|
| 4,634,918 | 4,634,902 |
| 4,401,190 | 4,401,174 |

The incumbent caller at `conversation_wired.dart:4590` prepares from the same source path used by the LAN and relay legs. No intervening iPhone photo transformation was observed in this inspected sequence. The uploader also verifies the durable plaintext copy has the originally measured length.

One unproven counterexample remains: an `EncryptedMediaArtifact` records `plaintextSize`, but the returned attachment uses a separately read source-file length. Reusing the artifact after that source path changes could produce a mismatch. No such source mutation was established in this incident or the inspected caller, so this is not an incident attribution or a proposed protection bypass.

## Validation performed

All **94 focused tests passed**, with no production or test source edits:

| Selection | Passed | Local log |
|---|---:|---|
| `private_media_policy_test.dart`, `message_payload_test.dart`, `conversation_message_test.dart` | 89 | `/tmp/private-media-policy-decoder-20260908.log` |
| Sender: valid private policy remains encrypted-inner-only and persists on parent | 1 | `/tmp/private-media-sender-existing-20260908.log` |
| Sender: private text rejected; guarded retry preserved; protected/view-once plural fanout | 3 | `/tmp/private-media-sender-preservation-20260908.log` |
| Uploader: returned attachment preserves plaintext size and uploaded ciphertext hash | 1 | `/tmp/private-media-upload-contract-20260908.log` |

These are nonoverlapping selections. They validate the stated source boundaries; they do not reproduce the actual photos, shipped iPhone binary, or failing receiver download.

## Existing failure-log accessibility

`lib/core/utils/flow_event_emitter.dart:6` defaults FLOW logging to `kDebugMode`, so it is normally disabled in release/profile. At `:258–261`, events go only to an optional E2E observer and enabled console output. `production_application_bootstrap.dart:532` permits the compile-time `FDC_FLOW_LOG` override, but it creates no durable file store.

The download failures at `download_media_use_case.dart:2108`, `:2146`, `:2177`, and `:2212` emit FLOW events for ciphertext-hash rejection, reported decryption failure/missing output, or plaintext-size mismatch. Their durable attachment status can collapse these causes to `integrity_failed`. The independent native audit additionally found that the existing `DECRYPT_ERROR` response can include file read/write failures, so that status is not proof of cryptographic corruption. Ordinary release logging cannot be assumed to retain the precise reason.

`push_diagnostics_logger.dart:16` prints and calls `developer.log`; it does not persist a file, and these download failures do not call it. The current Settings → Support → Call diagnostics preview exports only the call runtime's closed event archive (`call_diagnostics.dart:578`), not FLOW/private-media events. That newly added support surface cannot be assumed present in the shipped incident build.

The smallest useful receiver evidence is policy version/mode/lifecycle state, attachment download status, and plaintext size. A future classification record should retain a closed failure reason/stage, rather than copying FLOW details that may contain exception text or identifier prefixes. No photo bytes, private keys, raw hashes, message content, or peer identifiers are needed to distinguish these failure classes.

## Two-iPhone readiness check

| Target | Observed readiness |
|---|---|
| USB iPhone11 `00008030-001A6D2801BB802E` | Existing USB-pinned WDA on port18100 was ready with an active session. Phone was already unlocked; `com.mknoon.app` was foreground, version1.0.1/build111. |
| USB iPhone13 `00008110-00184D622289801E` | Physical target connected; WDA installed and an existing runner process present. Installed Mknoon was version1.0.1/build260907203036. A dedicated USB-pinned port18101 forwarding process was authorized and created, but GET status/lock-state requests immediately reset because the device WDA endpoint was unavailable. |

The existing `/tmp/beta-call-review-20260908/dual_phone_call_ui.py` helper is restricted to the Pixel/iPhone11 lab pair. No exact account/identity evidence established that the two iPhones were paired lab accounts; contact display names were not treated as proof.

**The two-iPhone reproduction was not performed.** The limits were WDA endpoint failure on the connected iPhone13 and unverified lab pairing, not unavailable physical hardware. No app activation/navigation, unlocking, installation, reset, or message sending occurred. Only the dedicated iPhone13 forwarding session created by this audit (2385) was stopped afterward; it exited130. Existing iPhone11 forwarding and other runner processes were left intact.

## Navigation context

Graphify packets used for source navigation, not runtime proof:

- Policy/model: `ecdfc22831544e93 / 523caee0d05153fd`.
- Decoder: `22fbc05a1d494050 / 693bd44c4456799c`.
- Inbound decrypt: `24c70136f4964d91 / 728d3fd66e96a1cd`.
- Sender: `07c7a81cae374eb6 / 4ce4e7348cf797bb`.
- Uploader: `50832c27eaf2421f / 41b9ceb6140c5150`.
- Go blob crypto boundary: `2a459f0ff50d44df / 19ffb1979b4cf5e4`.
- Logging: `c792f619d3a6438e / 759eda357e28b644`.
