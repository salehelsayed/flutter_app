# Native decrypt classification

A deterministic counterexample confirmed a classification bug: valid AES-GCM ciphertext with a directory blocking its plaintext output path returned the same legacy `DECRYPT_ERROR` as an authentication failure. The Dart download path previously treated that ambiguous code as permanent integrity failure. This does **not** establish what caused either historical photo to fail; no original client-side error was retained.

The native fix uses `errors.Is` classifications in `go-mknoon/crypto/file_crypto.go:17` and `:79`, preserving wrapped filesystem causes. `go-mknoon/bridge/bridge.go:3437` maps them to fixed, safe response codes/messages without exporting paths, keys, nonce values, raw errors or plaintext:

| Code | Meaning |
| --- | --- |
| `DECRYPT_AUTH_ERROR` | AES-GCM authentication rejected the bytes/key/nonce. |
| `DECRYPT_METADATA_ERROR` | Invalid key/nonce encoding or length; rejected before file I/O. |
| `DECRYPT_IO_ERROR` | Ciphertext read or plaintext output write failed. |
| `INVALID_INPUT` | Invalid outer request or missing file path; remains ambiguous. |
| `INTERNAL_ERROR` | Unexpected internal failure; remains operational. |

Success JSON and encryption behavior are unchanged. Invalid nonce lengths now receive an explicit metadata failure before `GCM.Open`. Old-binary `DECRYPT_ERROR` remains ambiguous; the separately reviewed Dart change treats it as a bounded operational failure without displaying or acknowledging bytes.

The focused regression was RED on the original classification (three top-level tests and nine nested cases failed). Final Go1.25.0 checks passed all 11 top-level tests and 20 nested cases. The valid blocked-output case returns I/O failure, then the same ciphertext recovers after the obstruction is removed (`bridge_test.go:5456`). Wrong-key/tampered bytes remain rejected, no output path is returned on failure, and tampered bytes never write plaintext (`bridge_test.go:5495`). Core tests preserve both typed I/O classification and `os.ErrNotExist`/`*os.PathError` causes (`file_crypto_test.go:111`). Metadata tests reject malformed values before I/O (`:151`).

Synthetic roundtrips at plaintext sizes 4,634,902 and 4,401,174 bytes produce ciphertext sizes exactly matching the reported 4,634,918 and 4,401,190 bytes; both and the existing 5 MiB case pass (`file_crypto_test.go:173`). No real user media was read. This rules out a deterministic size limit in the tested crypto helper at those sizes, not every possible runtime/filesystem failure.

Exact commands, test names, outcomes and frozen source hashes are in `native-classification-tests.json`. Binding rebuild provenance is recorded separately in `native-decrypt-bindings-build.json`. Existing delivered112 store packages were not rebuilt or modified by this work.
