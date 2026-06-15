# Integration Test Harness — Plain-English Report

**Date:** 2026-06-15
**Audience:** Non-technical / decision-makers
**Companion (for engineers):** `124-integration-harness-refactor-tdd-plan.md`
**Status:** Analysis complete (read-only — no tests were run, no code changed yet)

---

## 1. What this is about, in one paragraph

We have a large body of "end-to-end" automated tests — the programs that launch the
real app on phones and simulators and check that messaging, groups, media,
notifications, and account-move all actually work. This collection has grown to
**76 files and about 124,000 lines of code**. The tests are valuable and we want to
keep all of that coverage. The problem is **how slow they are to run**, and the fact
that **nobody has a single map** of what they cover, where they overlap, and where the
holes are. This report explains what we found and, more importantly, *how* we plan to
fix it safely.

---

## 2. Why the tests are slow (the core finding)

Every test program has to **build the app from scratch before it can run** — like
re-printing an entire book just to check one page. Building the app is the slow,
expensive step.

Running the full suite today triggers roughly **70 separate app builds**. That is the
single biggest reason the suite is slow.

Here is the key insight: **the team has already solved this problem once, in one
place.** One giant test file (`group_multi_party_device_real_harness.dart`) runs **106
different scenarios from just ONE build**. It does this with a simple trick — when it
starts up, it reads a label that says "which scenario am I running right now?" and
behaves accordingly. One build, 106 outcomes.

Everywhere *else*, we never reused that trick. So we have:

- **17 separate "benchmark" programs** that are nearly identical — 17 builds where 1
  would do.
- **5 pairs of "two-phone" tests** (an "alice" file and a near-copy "bob" file) — 10
  builds where 5 would do.
- **6 performance programs** and **4 group-simulation programs** that could each
  collapse to one.
- **8 tests that force a slow phone-build even though they don't need a phone at all** —
  they could run instantly on a plain computer instead.

---

## 3. What we found when we mapped everything

We ran an automated, read-only audit (12 specialist passes over the code) that produced
three things:

**A. A build-cost map.** ~70 builds today, split as roughly 8 real-phone builds, ~58
simulator builds, and 5 that already run the fast way. We traced exactly which file
causes each build and why.

**B. A duplication map.** The same work is being re-done in many places — for example,
"send a group message and confirm it arrives" is independently re-tested in at least 5
different programs, and small helper snippets (a fake login store, a database setup, a
"wait until connected" loop) are **copy-pasted across 9–24 files each**. When one of
these needs a change, someone has to edit it in a dozen places by hand, which is both
slow and error-prone.

**C. A coverage-gap map.** We compared what the tests cover against the app's real
features and found **10 genuine holes**, including some important ones:
- **Restoring an account from a recovery phrase** is not tested end-to-end (a returning
  user could be locked out and we wouldn't catch it).
- **The full "move my account to a new phone" flow** (transfer + switch-over + QR
  pairing) is only partly tested — and this is the riskiest feature we ship.
- **Sending/accepting a contact request** and **reactions** have no end-to-end test.
- Two security-sensitive group behaviors (reactions, removing a member) are tested
  **only inside the one giant file** — if that file ever breaks, we lose that safety net
  entirely.

---

## 4. How we're going to fix it (the approach, in plain steps)

The guiding principle is **"never break the safety net while improving it."** The suite
stays fully working at every single step, and every step can be undone.

1. **Take a baseline photo first.** Record exactly what every test does today, so we can
   prove later that nothing changed.

2. **Pull the copy-pasted glue into one shared toolbox.** Before merging anything, move
   the repeated helper snippets into a single shared library. This changes *no behavior*
   — it just stops the copy-paste — so it's the safest possible first move.

3. **Apply the "ask which one am I" trick to the four obvious places** (benchmarks,
   performance, group-simulations, and the alice/bob phone-pairs). This is the big
   win — it's the same proven approach, just reused. Each merge is done one family at a
   time and checked against the baseline photo.

4. **Let the tests that don't need a phone run on a plain computer instead.** Six tests
   currently demand a slow phone-build for no reason; we switch them to the fast path.
   (Two look similar but genuinely need a phone — we leave those alone.)

5. **Delete two pointless wrapper files** that add builds but no new coverage.

6. **Finally, fill the 10 coverage holes** using the new shared toolbox — especially the
   account-restore and account-move tests, since those are the highest-risk features.

---

## 5. What we expect to get out of it

| Measure | Today | After |
|---|---|---|
| **Separate app builds per full run** | ~70 | **~35** |
| Slow real-phone builds | ~8 | ~7 |
| Simulator builds | ~58 | ~23 |
| Coverage lost | — | **none** |
| Copy-pasted helper blocks | 8 (in 9–24 files each) | consolidated to 1 each |
| Untested high-risk flows | 10 holes | holes closed |

In plain terms: **roughly half the build cost removed, no coverage given up, the
duplication cleaned out, and the dangerous gaps closed** — with a clear map of the whole
suite for the first time.

---

## 6. What we are deliberately NOT doing

- **Not rewriting the big 106-scenario file.** It's the proof that our approach works
  and it's load-bearing. We may tidy its internals last, optionally, but it is not a
  prerequisite and it is not on the critical path.
- **Not reducing the number of phones a two-phone test uses.** Those tests genuinely
  need two real devices talking to each other; we only stop *building the app twice* for
  them, not *running* it twice.
- **Not touching the native (Go) build system** beyond what's necessary.
- **Not deleting any real test coverage** — every scenario that exists today still runs
  afterward.

---

## 7. Risk and confidence

This is a **low-to-medium risk** effort because of the order we do it in: the safe,
behavior-preserving cleanups come first and the suite is verified green after each step.
The one genuinely higher-risk move (running phone-tests on a plain computer) is fenced
off to the handful of tests we've confirmed don't actually need a phone, with the two
ambiguous ones explicitly left alone.

The detailed, engineer-facing plan — phase by phase, with the exact files, the
"prove-nothing-changed" checks, and the per-phase risk — is in the companion file
`124-integration-harness-refactor-tdd-plan.md`.
