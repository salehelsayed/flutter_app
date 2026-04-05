# 62 Session 4 Plan: Close UX-014 in Maintained Docs

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- update the maintained audit and architecture docs so they describe
  admin-initiated dissolve as landed repo behavior instead of unsupported scope
- remove `UX-014` from the unsupported-only tracker and close the matrix row
  with concrete proof references
- record the final doc-62 closure verdict after same-day verification is
  attached to the maintained docs

Out of scope for this session:

- new product or protocol work beyond what sessions `1` to `3` already landed
- broader redesign of the matrix or audit taxonomy
- reopening admin-transfer or multi-device scope that remains genuinely open

### Closure bar

Session `4` is done only when:

- maintained docs no longer describe admin-initiated dissolve as unsupported
- `UX-014` is closed with truthful proof references
- the doc-62 breakdown records the final program verdict and same-day
  verification evidence

### Source of truth

- active session contract:
  `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-breakdown.md`
- product/problem doc:
  `Test-Flight-Improv/62-admin-initiated-group-dissolve.md`
- maintained audit:
  `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- maintained architecture note:
  `Test-Flight-Improv/09-network-group-messaging.md`
- maintained matrix docs:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`

### Exact problem statement

The dissolve feature is now implemented and directly tested, but the stable
maintenance docs still say the journey is unsupported. Session `4` must make
the audit and matrix files match repo truth so future work does not reopen
`UX-014` unless a real regression appears.

### Files and repos to inspect next

Docs:

- `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`
- `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-breakdown.md`

Verification artifacts:

- session `2` and `3` direct tests
- same-day `./scripts/run_test_gates.sh groups` result

### Step-by-step implementation plan

1. Replace unsupported-scope wording in the audit and matrix docs with landed
   dissolve behavior plus proof references.
2. Update the network architecture note so it mentions `group_dissolved`,
   read-only retained history, send blocking, and rejoin skipping.
3. Remove `UX-014` from the unsupported-only tracker and record the new count.
4. Write the final program verdict in the doc-62 breakdown with the exact
   same-day verification evidence used for closure.

### Risks and edge cases

- do not overclaim repo-external scope such as admin transfer or multi-device
  convergence; only close dissolve
- keep proof references tied to tests actually run on `2026-04-05`
- preserve the distinction between ordinary leave and shared dissolve in the
  maintained docs

### Exact tests and gates to run

Required verification:

- targeted session `2` direct tests
- targeted session `3` presentation tests
- `./scripts/run_test_gates.sh groups`

### Done criteria

- `UX-014` is now closed in stable docs, not just in session plans
- future work should reopen doc `62` only on a real dissolve regression

### Scope guard

- do not invent new follow-up programs unless closure review finds a real gap
- keep this session doc-focused once verification is green
