# Small Codex Graphify token experiment — 2026-09-11

Ordinary targeted search was cheaper in all five sampled questions. Graphify
used 5,364 tool-result context tokens versus 3,541 for ordinary search, a
51.5% increase after both received the same current-source verification.
This supports ordinary search as the default. Removing the optional Codex
integration is reasonable for simplicity; its automatic hook is already off,
so removal would mainly eliminate instruction and maintenance overhead.

| Question | Ordinary search | Graphify | Shared verification included in each |
|---|---:|---:|---:|
| Find `ImageQualityPreference` definition | 109 | 444 | 91 |
| Find `CallAudioNegotiationPreparer` definition | 166 | 305 | 140 |
| Find production references to `GroupMediaIntegrityPolicy` | 942 | 1,165 | 657 |
| Find direct test importers of `background_message_handler.dart` | 388 | 629 | 198 |
| Find code starting/stopping caller-side ringback | 1,936 | 2,821 | 1,910 |
| **Total** | **3,541** | **5,364** | **2,996** |

These are exact counts under `tiktoken 0.14.0` / `o200k_base` of captured
command stdout plus stderr, used as a context-size proxy. They are **not total
task tokens, model-specific billing counts, or measured whole-agent savings**.
Adding encoded command arguments gives 3,884 versus 5,818 (+49.8%). Tool
envelopes, reasoning, repeated context processing, cache effects, experimental
setup, and final answers are excluded. Counting emitted text once cannot
determine how much a complete agent session would cost.

The Graphify skill text alone measures another 2,261 tokens when loaded. The
Graphify section in the repository's AGENTS.md measures 242 tokens. Neither is
included in the paired table; their actual session contribution depends on
instruction loading and reuse. Keeping unused graph files does not itself
inject their contents into model context.

Both methods located the exact current definition lines. Graphify's compact
reference result named 1 of 23 matching production files; its test result
named 1 of 7 direct importers. Ordinary search found all relevant candidates,
although its initial test basename search included eight additional files
that mention the source path without importing it. The shared import check
removed those extras. These counts concern explicit symbol references and
imports, not exhaustive behavioral coverage or transitive dependencies.

For ringback, filename discovery found both relevant files immediately.
Graphify returned broad bootstrap context, then needed one linked refinement
and a source search in that bootstrap file to discover the same files. All
those steps are charged to Graphify. Subsequent source verification was
identical between methods. All executed benchmark commands exited zero;
the quality assertions passed.

The five tasks and initial commands were saved before executing either method.
Execution alternated search/graph order. Graphify used the installed helper
and prescribed general/review/TDD budgets of 600/800/700. Ordinary search used
targeted `rg` definitions, symbol file lists, test filename mentions, and
ringback filename discovery. Both were charged targeted source checks rather
than assumed full-file reads. Definition searches already provide their
answer, so charging extra verification to those raw searches is conservative.

This is one small, manually selected retrieval experiment, predominantly about
known symbols. It does not test complex architectural reasoning, debugging,
multi-agent reuse, or a freshly rebuilt graph. No independent agent A/B was
run. Every graph result reported stale source state; this experiment measures
the existing configuration and graph as requested. The graph was not rebuilt.

HEAD: `e7e11bab2243a57fbc035236a83409e26c9248e5`.
Graph fingerprint reported by the helper: `0d715cad021b680b`.
The working-tree status remained unchanged during measurement. This report is
the only repository file added by the experiment. Project and saved user
configuration both disable the Graphify hook for this workspace.

Questions, exact commands, full outputs, counts, hashes, and executable local
harness are retained in the temporary artifact directory:

`/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/graphify-token-experiment-20260911-2bx3tx04`

Start with `summary.json`, `manifest.json`, and `initial-results.json` there;
the ringback refinement and all source checks have separate JSON records.
These artifacts are temporary and may be removed by normal system cleanup.
