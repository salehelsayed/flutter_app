# Session 41 Plan — Cross-Slice Acceptance And Closure Refresh

## Real Scope

What changes in this session:

- refresh the stable closure/docs set so it matches the landed Sessions `38`,
  `39`, and `40` behavior
- update the gate classification source of truth for any new direct test files
  introduced during this rollout
- record the current-turn acceptance evidence for the required named gates

What does not change in this session:

- no new product behavior
- no new transport/runtime architecture
- no reopening of already-accepted Session `38`, `39`, or `40` code unless a
  verification step proves a real regression

---

## Closure Bar

This session is sufficient when all of the following are true:

- `scripts/run_test_gates.sh` and
  `Test-Flight-Improv/test-gate-definitions.md` classify the new Session `40`
  direct test coverage cleanly
- the stable 1:1 and group closure references explicitly reflect:
  - the settled `5 GB` general-media budget for ordinary attachments
  - the separate `100 MB` in-app voice-recording sanity limit
  - the honest foreground-only upload protection that landed in Session `40`
- stale `UI-10-Media` specs no longer claim the old `100 MB` general-media cap
  or imply stronger upload behavior than the repo actually ships
- verification is recorded with:
  - `./scripts/run_test_gates.sh completeness-check`
  - current-turn green evidence for `baseline`, `1to1`, and `groups`

---

## Source Of Truth

Authoritative sources for this session:

- proposal and breakdown:
  - `Test-Flight-Improv/22-media-transfer-size-limit.md`
  - `Test-Flight-Improv/22-media-transfer-size-limit-session-breakdown.md`
- stable closure/docs owners:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `UI-10-Media/media-server-spec.md`
  - `UI-10-Media/media-client-spec.md`
- landed code reality checks:
  - `go-relay-server/media.go`
  - `lib/core/local_discovery/local_media_server.dart`
  - `lib/features/conversation/application/send_voice_message_use_case.dart`
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/conversation/presentation/widgets/upload_progress_banner.dart`
  - `scripts/run_test_gates.sh`

Conflict rules:

- landed code wins over stale prose
- `scripts/run_test_gates.sh` wins over `test-gate-definitions.md` if they
  ever drift; this session must leave them aligned again
- Session `40` acceptance evidence already gathered in the current turn counts
  as the verification baseline unless a new doc/script change requires more
  proof

---

## Files To Touch

- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `UI-10-Media/media-server-spec.md`
- `UI-10-Media/media-client-spec.md`
- `Test-Flight-Improv/22-media-transfer-size-limit-session-breakdown.md`

---

## Planned Verification

- `./scripts/run_test_gates.sh completeness-check`
- use current-turn green evidence for:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh 1to1`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`

Stop rule:

- if the stable docs and landed code disagree in a way that would require new
  production behavior, stop and reopen implementation instead of silently
  rewriting the docs to overclaim closure
