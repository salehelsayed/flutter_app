# Private photo incident — 8 September 2026

The user reports two iPhone-to-iPhone photos, one protected and one view-once, sent around 20:06 Europe/Berlin. Both participants use version 1.0.1 (111). The recipient returned an error screenshot around 20:07. These times strongly correlate the reported photos with relay aliases `blob4` and `blob5`; correlation uses timing and direction, not decrypted content.

## Established findings

| Event | UTC | Relay evidence |
| --- | --- | --- |
| First photo | 18:06:11.824 upload; 18:06:51.553 download | 4,634,918 encrypted bytes transferred; no cleanup acknowledgement |
| Second photo | 18:06:59.737 upload; 18:07:04.644 download | 4,401,190 encrypted bytes transferred; no cleanup acknowledgement |
| Returned screenshot candidate | 18:07:56.492 upload | Downloaded and explicitly deleted by its recipient |

Both photo files remained on the relay at the bounded follow-up check. Each has one upload and one matching-byte download, unchanged upload timestamps, and no observed replacement, truncation, or media-transfer error. The relay stores encrypted bytes; it has neither the private policy nor the recipient's expected ciphertext hash in these legacy sidecars. See [relay review](relay-private-media-review.md) and [exact metadata](relay-exact-two-photo-metadata.json).

The app's update instruction is also used for `integrity_failed` and inconsistent policy/lifecycle state, not just a newer unsupported policy. That is a confirmed misleading error-display bug. A supported private-media parent is required before the current direct-download path requests bytes, making post-download validation a stronger candidate than an initial version rejection for these transferred photos. The exact historical rejection remains unproved without receiver evidence; a completed relay write does not establish durable client acceptance or display.

Native protection registration is unconditional. Native protection failures and notification-service preview handling do not directly write an unsupported message policy. Current sender/model audits found no demonstrated producer of invalid policy or mismatched size/hash for this incident. Matching display version alone does not establish an exact source revision for the friend's installed binary.

## Changes made

- A demonstrated decryption error-classification bug is corrected. The native helper previously reported both a failed authentication and a failed file read/write as `DECRYPT_ERROR`. Dart then treated every negative reply as a `StateError`, which permanently quarantined the attachment. A valid authenticated ciphertext whose output cannot be written reproduces this defect; it does not establish that the friend's phone encountered that particular filesystem error.
- Native responses now distinguish `DECRYPT_AUTH_ERROR`, `DECRYPT_METADATA_ERROR`, and `DECRYPT_IO_ERROR`. Invalid nonce length is checked explicitly. Failure messages exclude native paths and raw error text.
- Dart reserves permanent crypto rejection for the two explicit authentication/metadata codes. Direct-media I/O, unavailable transport, malformed responses, and ambiguous legacy errors use the existing bounded operational retry path. Private plaintext/staging cleanup and relay retention remain under their existing owners; no relay cleanup acknowledgement is sent for failed acceptance. The receiver UI offers Retry while the durable status/budget permits it.
- The private-media card now reserves update advice for a newer policy version. Current-version malformed metadata, inconsistent saved state, and integrity quarantine use the existing localized “Couldn't verify this media” copy.
- The Info dialog uses neutral verification-failure copy for unsupported state, so it does not repeat the misleading update instruction.
- Successful decryption, current-row authority, lifecycle, capture-protection, and export restrictions remain required. Existing quarantined rows are not automatically reopened: their old status does not distinguish authentic corruption from the earlier classification bug.

## Validation

- The causal card regression failed before the change, then all 8 card tests passed, including an actual Info tap and preservation of future-version advice.
- 52 focused viewer/tile/action-policy preservation tests passed.
- The new bridge causal tests failed 16 of 17 cases before the correction; afterward 17 new and 17 existing helper tests passed.
- All 107 combined download/new-bridge tests passed. The new real-database regression covers protected and view-once media against explicit authentication/metadata failures and I/O/legacy failures. It verifies no plaintext exposure or relay acknowledgement on failure, permanent crypto denial, successful operational recovery, and an unchanged available view-once lifecycle after download.
- The final combined curated `1to1` host lane passed: **3,562 tests, 4 skipped, 213 test paths**, including the new bridge regression registration. Counts overlap focused runs and must not be added.
- Native checks passed: 11 top-level tests with 20 nested cases, including both observed payload sizes and a 5 MiB roundtrip. See [native classification proof](native-classification.md).
- Post-media and private-card preservation: 15 tests passed. Review of all six decryption call sites found no new display/commit/ACK bypass. Ordinary-group catch-all quarantine behavior is unchanged; this is a direct-media recovery fix.
- The first broader core lane found two failures from one stale bootstrap hash left by the earlier authorized nine-line call-diagnostics initialization. The exact source delta was reviewed; only that baseline and its explanation changed. The architecture assertions remained intact, and all three exact architecture tests passed. The final core lane then passed **3,845 tests across 448 test paths**, plus both Android manifest contracts.
- All nine affected Dart source/test files analyzed without issues; diff whitespace check passed.
- Architecture impact analysis and incremental graph refresh completed for the combined code changes and preservation-test adjustments.

## Remaining evidence limit

Ordinary store builds disable FLOW logging by default. Enabling it at compile time provides console output, not durable private-media diagnostics. The existing Call diagnostics export does not include these media events. Thus the relay cannot retroactively distinguish ciphertext-hash mismatch, decryption rejection, plaintext-size mismatch, or a later local-state failure.

Receiver-side metadata needed for further attribution is limited to policy version/mode/lifecycle, attachment download status, and a closed validation stage/reason. No photo, caption, encryption key, nonce, or plaintext content is needed. With the existing AES-GCM contract, the two transferred blobs imply plaintext lengths of 4,634,902 and 4,401,174 bytes; these remain expected values until compared with receiver metadata.

Android and iOS full/NSE bindings were rebuilt and passed their API guards. Previous bindings are backed up under `build/private-media-fix-backups/20260908T190426Z-before-decrypt-classification/`. See [native build provenance](native-decrypt-bindings-build.json).

No relay deployment changed. Previously delivered 1.0.1 (112) AAB and IPA hashes were rechecked and match the delivered artifacts; those files do not include these corrections. No new store release, installation, or upload is claimed. A new receiver build and a fresh send are needed to validate the original user journey; this report does not claim a live reproduction on the friend's phone.
