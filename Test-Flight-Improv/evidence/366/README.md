# Plan 366 Final-Tree N01 Mechanism Closure Receipt

Date: 2026-08-15 (Europe/Berlin)

This receipt supersedes the earlier Plan-366 execution summaries for dependency
purposes. Those summaries were directionally correct, but their retained logs
predated three final counterexample fixes. The commands below were rerun on the
same frozen final source/test tree after those fixes. No additional N01 product
change was needed.

## Verdict

- `N01_MECHANISM_CODE_COMPLETE = true`
- `N01_LIVE_ACCEPTANCE_PROVEN = false`
- Both relay custody admissions remain default-off.
- N02 planning and host implementation may depend on this receipt.
- S2 authorization, deployment, cumulative Android B1b, rollback evidence,
  persistent activation, and release eligibility remain WP-07 obligations.

This receipt does not claim an S2 deployment, a live B1b pass, a release
decision, or permission to enable either admission.

## Final causal and preservation results

| Proof | Final result |
|---|---|
| Direct Plan-366 focused bundle | 25 `TC-366-*` tests selected; zero skipped, zero errored |
| Group/history Plan-366 focused bundle | 17 `TC-366-*` tests selected; zero skipped, zero errored |
| Curated `1to1` | `+3205 ~10: All tests passed!`; registered relay tails passed |
| Curated `groups` | `+4199: All tests passed!`; registered relay tails passed |
| N01-wave `host-all` | exit 0; exactly 1,355 sequential `PASS` records; zero `FAIL` records; final scope marker present |
| Test inventory completeness | `1445/1445`; PASS |
| Flutter analyzer | `No issues found!` |
| Check-only hygiene | 184 dirty Dart files, 0 formatting changes; 13 Go files, `gofmt` clean; `git diff --check` clean |

The final serial wave command started at
`2026-08-15T03:56:21+0200` and finished at
`2026-08-15T05:30:27+0200`. Its last line is
`PASS: host tests completed for scope: host-all`.

The hygiene wrapper's first shell attempt exited before its Go loop because a
zsh loop variable named `path` shadowed zsh's command-search array. That is a
test harness invocation error, not a source or product failure. Completeness
and analyzer had already passed. The check-only format, `gofmt`, and diff steps
were immediately rerun with `file_path`; the result recorded above is exit 0.

## Frozen tested state

The shared worktree was intentionally dirty. An alternate index captured all
tracked files plus untracked, nonignored files without replacing or writing the
shared index.

| Identity | Value |
|---|---|
| Base and unchanged `HEAD` | `3865aa9b8b8b000ecaf871a839d1fbdecaa0d86c` |
| `HEAD` tree | `a0a945780c196f16d852906607ed85a103770e59` |
| Frozen tested tree | `0765646f6c60140424e5320552d38ed0e5a2fce8` |
| Porcelain-v2 workspace snapshot SHA-256 | `dc81e2b00819e00acac0b315ef2b9e42830aa4c1e562ed68aec841773f61f81f` |
| Shared-index entries SHA-256 | `facebfda6c4be99f6ff1760e1cdd647ff2259763d6cc2acca9abdaff6a200178` |
| Shared-index byte SHA-256 | `cfa02381018fbb5d3da0f1c137c278bb07d7f1d2bfe7bda0a863105143d87226` |

The first machine snapshot was captured while `host-all` was already running,
so it is honestly named **MID**, not PRE. MID, the immediate POST snapshot at
`2026-08-15T05:31:00+0200`, and the hygiene POST snapshot at
`2026-08-15T05:34:25+0200` have the same frozen tree, porcelain hash, index-entry
hash, and index-byte hash. The executor attests that no source or test edit was
made between command launch and MID; machine-proven equality begins at MID.

No commit, synthetic commit, or tag was created. This README, its checksum, and
the compressed evidence archives postdate the run and are intentionally absent
from the frozen tested tree.

## Graph grounding

The already-refreshed app architecture graph covering the final N01 source had:

| Graph fact | Value |
|---|---|
| Fingerprint | `19e306d1432ccbf1` |
| Nodes / links | 75,335 / 109,759 |
| Named tests / test files / registered files | 15,646 / 1,571 / 1,491 |
| `graph.json` SHA-256 | `7c4cf3f46b9a8478393d523378649fa2f5a7078d3eb9f0fb86c7137bc11dbc63` |
| `manifest.json` SHA-256 | `2f4aba72c3fde228e0e098bbeeb82b0cfd9ac620eae210cc9fe81ccd370548b7` |
| TDD overlay SHA-256 | `22a4afd1e921f6cb25c91ed79d6d75a23a6dee38b97ad80fff7ab989cd110f92` |

No graph refresh was necessary merely because tests ran.

## Retained artifacts

Every archive was produced deterministically with `gzip -n -9`. Decompressing
it reproduces the raw SHA-256 shown below.

| Artifact | Raw bytes | Raw SHA-256 | Archive bytes | Archive SHA-256 |
|---|---:|---|---:|---|
| `plan366-direct-final.json.gz` | 214,669 | `eb2809ba7538b3d4ab5ed0781bd215c89eefa1343f1f200c55446bb7879434f9` | 14,588 | `a8f8340996d3fee79118fc2fe9e309002afe870e496eee5db0c7d354fe096292` |
| `plan366-group-history-final.json.gz` | 120,586 | `08c0d0f22da41d8d66afd90758f5cff8cf599a14dcf4ab220768913df515075a` | 9,767 | `d3084c236be08bffdcdb69e63b1c85c8b907f272a91845ca018d518c9adb386d` |
| `plan366-curated-1to1-final.log.gz` | 4,001,125 | `24c0fdf4ca5bb16e437e8bd01d48931f13fe366ca80b8fdd91fb7e3f8388d4c5` | 296,620 | `d1b0ab1f8988bdfd68e57fcda521656c23f56190fcb6e4a5cf8bab80fe284df9` |
| `plan366-curated-groups-final.log.gz` | 10,881,465 | `0ab4492c7658bdea99fe16f1212760ff0dc3acacde2f367bb192ce7753fa6192` | 751,575 | `a09a5f937f20b535c1b1e25fe1efd18ac639ef91eb9c0ae8dc6c333da1256961` |
| `plan366-host-all-final.log.gz` | 16,962,042 | `c510bd74eb18e1081de181b0fea94e38b295bc1c76b3dc52db64dbb8060f5e07` | 1,467,375 | `0d0b75eaa90eca08d1c5d56c9b0be521fed58cf285ab539c8db84157be78f142` |
| `plan366-flutter-analyze-final.log.gz` | 98 | `3ca33ca5bd0adba6171d65b1f210a7c3170fae1956d8e2ad990eec946d73f135` | 81 | `79390bc483f459efdb5757070effe9ca7bf5d282650119530ce43101ce9d52c3` |
| `plan366-completeness-final.log.gz` | 78 | `6036d69eeed8fe66b31bc4720da3b9cd8d35f5cd875f1338d92c4931154dad77` | 79 | `d572e03b57872e124f2a986ec2b5c82c51319bd995531cbca984d66e04a53229` |
| `plan366-hygiene-final.log.gz` | 127 | `5820ea42f5e0efb74b488699c9952d968290630f71d8b83a07751976cf14b485` | 126 | `fe8bae88fa4e8e2284962e6d71389749f918e12eab70d16256e10e7e9607c822` |

## Dependency handoff

Plans 367 and 368 may use this exact receipt as the N01 mechanism dependency.
They must not reinterpret it as live acceptance or release eligibility. The
Plan-365 media/voice B1b remains a single later acceptance operation using the
available USB Android plus Android emulator, with explicit S2 authority and
mandatory restoration of both admissions to off.
