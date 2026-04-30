# LP-001 Session Plan: Group PubSub Topic Derivation Avoids Human-Readable Metadata

## Source Row

- source matrix: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- source row id: `LP-001`
- scenario: Group PubSub topic derivation avoids human-readable metadata
- current source status: `Partial`
- priority: `P0`
- row disposition: `repo_external_proof`
- session classification: `evidence-gated`
- dependency: none

## Scope

- Prove Go-side group topic and rendezvous namespace identifiers derive from
  `groupId`, not human-readable group name or description.
- Fix any adjacent repo-local log leak found while proving the row.
- Keep this session limited to PubSub/rendezvous naming and diagnostics. Do
  not broaden into push payloads, relay-visible participation metadata, or the
  wider SP-002 metadata-minimization row.

## Expected Code And Test Touches

- Primary implementation:
  - `go-mknoon/node/pubsub.go`
- Primary tests:
  - `go-mknoon/node/pubsub_test.go`
- Source docs after execution:
  - `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

## Execution Steps

1. Inspect Go PubSub, rendezvous, and bridge group-create code for topic,
   namespace, and log construction.
2. Remove any log output that includes `GroupConfig.Name` or
   `GroupConfig.Description` while joining group PubSub topics.
3. Add direct Go tests proving:
   - topic names and rendezvous namespaces equal `/mknoon/group/<groupId>`;
   - sensitive group name/description strings are absent from those identifiers;
   - the group topic join log omits sensitive group name/description strings.
4. Update the source matrix and inventory with concrete file/test evidence.

## Required Verification

- Direct gate:
  - `cd go-mknoon && go test ./node/ -run 'TestGroupTopicName|TestGroupTopicAndRendezvousNamespace_DoNotUseHumanReadableMetadata|TestJoinGroupTopic_LogOmitsHumanReadableMetadata' -v`
- Broader row gate when feasible:
  - `cd go-mknoon && go test ./crypto/ ./internal/ ./node/ ./bridge/ ./cmd/testpeer/ -run 'Group|Announcement|Watchdog.*Group' -v`
- Hygiene:
  - `git diff --check`

## Done Criteria

- No group topic or rendezvous namespace test evidence includes human-readable
  group metadata.
- The PubSub join log does not print group name or description.
- LP-001 source row and `test-inventory.md` truthfully record the closure
  evidence.
- The breakdown ledger records LP-001 as `accepted` only if the source row is
  updated to `Covered`; otherwise it records the exact remaining privacy proof
  gap.

## Scope Guard

- Do not claim closure for SP-002, push payload privacy, relay content privacy,
  or broad diagnostics minimization.
- Do not replace opaque group ids with a new hash scheme in this session; the
  existing group-id-derived topic contract is sufficient if metadata-free.
