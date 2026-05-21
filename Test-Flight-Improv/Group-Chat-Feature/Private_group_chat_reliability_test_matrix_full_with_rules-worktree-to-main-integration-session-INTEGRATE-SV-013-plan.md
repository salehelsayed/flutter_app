# INTEGRATE-SV-013 Minimal Integration Contract

Status: accepted

## Scope

Import/reconcile source row `SV-013` from the full-with-rules worktree into main: logs and diagnostics must not expose group keys, plaintext, invite content, ciphertext, nonce values, private keys, or peer multiaddrs in group failure paths.

This is standard worktree-to-main integration, not new implementation rollout and not gap closure. The historical source plan remains the source of truth:

`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-013-plan.md`

## Reconciliation

- Source status: accepted/covered in the historical worktree.
- Main status before import: partial. Current main already had broad flow-event sanitization and existing ER-005 privacy coverage, but push diagnostics still formatted raw detail values and the sanitizer lacked row-owned plaintext/invite assignment coverage.
- Imported delta: expanded shared diagnostic sanitization for group plaintext and invite content assignments, private/secret key blocks, and multiaddrs; routed push diagnostic details through the same sanitizer; added row-owned bridge and push diagnostic redaction tests.
- Current-main adaptation: preserved existing media-key and invite-token redaction behavior while adding the missing SV-013 group-specific sensitive fields.
- Live proof: not required. Source 3-Party E2E is `N/A`; no iOS 26.2 simulator proof is claimed.

## Imported Artifacts

- `lib/core/utils/flow_event_emitter.dart`
  - Adds row-owned plaintext/invite sensitive keys and broader sensitive assignment redaction.
- `lib/core/utils/push_diagnostics_logger.dart`
  - Sanitizes push diagnostic details before stdout/developer logging.
- `test/core/bridge/go_bridge_client_test.dart`
  - Adds SV-013 bridge failure and push diagnostic redaction selectors.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- This contract.

## Verification

- PASS: `cd go-mknoon && go test ./node -run 'Test(ER001InvalidSignatureDiagnosticsArePrivacySafeAndActionable|PL014MediaMetadataAndProgressEventsDoNotExposeSecrets|IR014BuildGroupInboxStoreRequest_PreservesOpaqueReplayEnvelope)$' -count=1`
- PASS: `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "SV-013"`
- PASS: `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name "ER005"`
- PASS: `flutter analyze --no-pub lib/core/utils/flow_event_emitter.dart lib/core/utils/push_diagnostics_logger.dart lib/core/bridge/go_bridge_client.dart test/core/bridge/go_bridge_client_test.dart`
- PASS: `dart format --set-exit-if-changed lib/core/utils/flow_event_emitter.dart lib/core/utils/push_diagnostics_logger.dart test/core/bridge/go_bridge_client_test.dart`
- PASS: scoped `git diff --check`

## Closure

`INTEGRATE-SV-013` is accepted as host/native-only. Adjacent rows `SV-014` and later remain separate pending integration sessions.
