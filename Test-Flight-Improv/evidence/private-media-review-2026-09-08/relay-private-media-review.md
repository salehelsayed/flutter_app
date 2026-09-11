# Recent private-media report: bounded relay review

Reviewed **2026-09-08 18:05:00–18:40:10 UTC** using the retained `relay-server` journal and 15-second Prometheus samples. After the user's timestamp clarification, an additional exact-two-blob metadata/stat check covered retained current-service history **16:19:00–18:47:50 UTC**. No service, code, device or store-artifact changes were made.

## Finding

The user subsequently confirmed sending the first two images at **20:06 Berlin (18:06 UTC)** and receiving the friend's error screenshot at **20:07 Berlin (18:07 UTC)**. That provides a strong temporal/directional correlation: `blob4` and `blob5` are the reported photo pair, while the reverse-direction `blob6` corresponds to the returned screenshot. This mapping is based on the user's timing and direction, not plaintext inspection or a cryptographic message-identity match.

Both photo transfers have successful server-side upload and matching complete download records. Both files remain on the relay without later modification or recipient deletion. No relay truncation or replacement evidence explains the receiver's refusal to open them. The remaining distinction—receiver integrity rejection versus failed local durable commit or another receiver validation state—cannot be established from the relay metadata.

The following times are UTC. Aliases are local to this capture; they are not user identities.

| Blob / correlation | Direction | Upload completed | Matching download completed | Later deletion | Ciphertext bytes |
| --- | --- | --- | --- | --- | --- |
| blob4 / first reported photo | peer1 → peer5 | 18:06:11.824 | 18:06:51.553 | Not observed through 18:47:50 | 4,634,918 |
| blob5 / second reported photo | peer1 → peer5 | 18:06:59.737 | 18:07:04.644 | Not observed through 18:47:50 | 4,401,190 |
| blob6 / returned screenshot | peer5 → peer1 | 18:07:56.492 | 18:07:59.507 and 18:08:14.518 | 18:08:14.900 | 496,683 |
| blob7 / later unassigned transfer | peer5 → peer1 | 18:13:44.470 | 18:13:48.192 and 18:14:11.771 | 18:14:12.226 | 1,178,492 |

The returned screenshot has recipient-initiated deletion after download; the two reported photos do not. This discriminates their observed cleanup behavior, but does not alone distinguish integrity quarantine from local persistence failure. Neither deletion nor transfer completion proves successful decryption, policy validation, integrity acceptance or image display.

## Exact photo metadata and retry check

At 18:47:50 UTC, both exact blob sidecars and encrypted files remain present. Each has one completed upload, one completed download and zero same-ID reuploads or deletions in the current-service journal interval. No incomplete-upload, failed-commit or download-stream-failure entry references either blob.

For `blob4`, the file is 4,634,918 bytes, matching its declared size and both transfer logs. File mtime is 18:06:11.811, sidecar mtime 18:06:11.821 and recorded creation 18:06:11.823. For `blob5`, the corresponding size is 4,401,190 bytes; file mtime is 18:06:59.724 and sidecar/creation time is 18:06:59.734. There is no later modification indicated by these stat records.

Both legacy sidecars identify MIME only as `application/octet-stream`. Neither stores a ciphertext hash nor a private-media policy field. No image/ciphertext body was opened, read or hashed. The expected hash inside the encrypted application envelope is therefore unavailable for comparison; matching sizes do not rule out same-length corruption or a receiver-side hash/decryption mismatch. This evidence supports complete relay transfer without observed replacement, not a complete integrity proof.

## Counts and errors

The capture parsed 7,886 journal records without truncating its 726 allowlisted events. It contains 14 successful upload completions covering six distinct uploaded blob aliases, eight completed downloads and four explicit deletions. Nine upload completions are repeat uploads of one other 907,808-byte blob (`blob1`) to `peer2`; raw upload count is therefore not a count of new photos. A seventh touched blob was downloaded after an upload outside this window.

There are no journal events for media upload incompleteness, commit failure, file creation failure, media decode/read/write error or download-stream failure. All eight logged ordinary download requests have matching completion logs. Profile downloads are a separate 116-request category and are not counted as attachment transfers. There are 89 successful push-provider results and no provider failure/retry result in this filtered window; those outcomes cannot be uniquely assigned to a photo.

One separate legacy inbox store failure occurs at **18:35:31.570**, peer5 → peer1. Its error is retained as `unknown_redacted` because it did not match the fixed safe classifications used for this review. It occurs after the reported photos and returned screenshot and cannot be tied to either photo. It must not be omitted from the report or treated as the demonstrated cause.

## Custody and service state

Protected blob-custody admission stayed **disabled** (`relay_media_custody_admission_enabled=0`). All protected blob-custody outcome counters remained zero, and there were no `upload_custody_v1` or `ack_custody_v1` requests. The observed attachment transfers use ordinary `upload`, `download` and `delete`. A disabled feature flag is not evidence that a strict request was rejected: no such request/rejection was observed here.

Protected **inbox** custody is a different subsystem: admission stayed enabled, with 89 stored outcomes and zero disabled, duplicate, ineligible, identity-conflict, full or failed outcomes over the sampled window. These encrypted-envelope outcomes do not reveal the receiver's media policy or validation state.

Relay, coturn and Prometheus were active/running with `NRestarts=0` at capture. The relay has remained active since 16:19:10 UTC. No deployment change is justified by this evidence alone.

## Proof limits and sources

Current `go-relay-server/media.go` logs ordinary upload success after committing the blob and logs download success after `io.Copy` completes. The matching byte counts here establish server-side encrypted-byte transfer, not receiver rendering. `media_custody.go` has separate strict admission/identity/hash outcome counters. The relay does not decode the message's end-to-end encrypted private-media policy, application integrity state or viewer decision. Same app version and device platform come from the user's report, not these relay logs.

Graph navigation contexts: `22e7f3d828644b38` / `961ba55327a50ed8` for inbox custody; `db26cd513d874cd7` / `cb5c79aeb2a76568` for media transfer; `2e27622263a94566` / `967da3015c4f96f9` for exact metadata paths. Load-bearing claims were checked in current source. Evidence files: `relay-private-media-window.json`, `relay-private-media-error-classification.json`, `relay-private-media-summary.json`, and `relay-exact-two-photo-metadata.json`.

No raw peer/blob identifiers, hashes, image contents, chat plaintext, credentials, environment contents, IP addresses or exception text were exported. Peer aliases use the truncated 20-character prefix present in existing logs and cannot prove globally unique identities. The user's independently supplied attempt/screenshot times strengthen the photo mapping; no plaintext inspection, privacy-mode verification or cryptographic message-identity match is claimed.
