#!/usr/bin/env python3
"""FDC-S0 host-gate baseline back-fill. Deterministic, verified per-slot.
Replaces the FIRST occurrence of `old` on the given 1-based line, only if the
line actually contains `old` (else reports MISMATCH and skips). Idempotent-ish:
re-running after success reports MISMATCH for already-filled slots (safe)."""
import os, sys

BASE = "/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Network-Transport-libp2p-Feature/fast-direct-connection"

V_1to1     = "1226"
V_feed     = "279"
V_groups   = "896"
V_baseline = "112 host"
V_transp   = "device/fixture-gated (skips on lone sim)"
V_gomknoon = "all pkgs PASS / 0 fail (go1.25.0, ~1171 tests)"
V_gorelay  = "191 pass / 0 fail / 2 skip"
V_posts    = "device-gated suites (not captured this wave)"

# (file, line, old_token, new_token)
SLOTS = [
  ("FDC-01-direct-timeout-misroute-fix-tdd-plan.md", 172, "TODO", V_1to1),
  ("FDC-01-direct-timeout-misroute-fix-tdd-plan.md", 175, "TODO", V_transp),
  ("FDC-01-direct-timeout-misroute-fix-tdd-plan.md", 178, "TODO", V_feed),
  ("FDC-01-direct-timeout-misroute-fix-tdd-plan.md", 179, "TODO", V_groups),

  ("FDC-02-staggered-ranked-race-lan-priority-tdd-plan.md", 361, "TODO", V_1to1),
  ("FDC-02-staggered-ranked-race-lan-priority-tdd-plan.md", 364, "TODO", V_transp),
  ("FDC-02-staggered-ranked-race-lan-priority-tdd-plan.md", 367, "TODO", V_feed),
  ("FDC-02-staggered-ranked-race-lan-priority-tdd-plan.md", 368, "TODO", V_groups),
  ("FDC-02-staggered-ranked-race-lan-priority-tdd-plan.md", 369, "TODO", V_baseline),

  ("FDC-03-concurrent-durable-inbox-safety-net-tdd-plan.md", 261, "TODO", V_1to1),
  ("FDC-03-concurrent-durable-inbox-safety-net-tdd-plan.md", 264, "TODO", V_baseline),
  ("FDC-03-concurrent-durable-inbox-safety-net-tdd-plan.md", 265, "TODO", V_feed),
  ("FDC-03-concurrent-durable-inbox-safety-net-tdd-plan.md", 266, "TODO", V_groups),

  ("FDC-04-lan-aware-eager-warmpeer-tdd-plan.md", 352, "TODO", V_transp),
  ("FDC-04-lan-aware-eager-warmpeer-tdd-plan.md", 355, "TODO", V_feed),

  ("FDC-05-parallel-resume-reprime-tdd-plan.md", 328, "TODO", V_1to1),
  ("FDC-05-parallel-resume-reprime-tdd-plan.md", 331, "TODO", V_transp),

  ("FDC-06-graceful-pause-flush-tdd-plan.md", 353, "<TODO baseline>", V_1to1),
  # FDC-06:350 (core-host-all) intentionally deferred until that run completes.

  ("FDC-07-cold-start-early-mdns-reserve-tdd-plan.md", 309, "<TODO>", V_gomknoon),
  ("FDC-07-cold-start-early-mdns-reserve-tdd-plan.md", 313, "<TODO>", V_1to1),
  ("FDC-07-cold-start-early-mdns-reserve-tdd-plan.md", 320, "<TODO>", V_transp),

  ("FDC-09-foreground-self-publish-push-hardening-tdd-plan.md", 507, "count: TODO", "count: " + V_gorelay),
  ("FDC-09-foreground-self-publish-push-hardening-tdd-plan.md", 513, "count: TODO", "count: " + V_transp),
  ("FDC-09-foreground-self-publish-push-hardening-tdd-plan.md", 514, "count: TODO", "count: " + V_posts),
  ("FDC-09-foreground-self-publish-push-hardening-tdd-plan.md", 515, "count: TODO", "count: " + V_1to1),

  ("FDC-10-durable-inbox-redis-pool-tdd-plan.md", 189, "TODO baseline count", V_gorelay),
  ("FDC-10-durable-inbox-redis-pool-tdd-plan.md", 196, "TODO baseline count", "all pkgs green / 0 fail (go1.25.0, ~1171 tests)"),
  ("FDC-10-durable-inbox-redis-pool-tdd-plan.md", 198, "TODO count", V_transp),
  ("FDC-10-durable-inbox-redis-pool-tdd-plan.md", 200, "TODO count", V_1to1),

  ("FDC-18-reaction-send-reliability-tdd-plan.md", 308, "TODO", V_1to1),
  ("FDC-18-reaction-send-reliability-tdd-plan.md", 311, "TODO", V_groups),
  ("FDC-18-reaction-send-reliability-tdd-plan.md", 314, "TODO", V_feed),
  ("FDC-18-reaction-send-reliability-tdd-plan.md", 315, "TODO", V_baseline),

  ("FDC-00-roadmap.md", 360, "TODO", V_1to1),
  ("FDC-00-roadmap.md", 364, "TODO.", V_transp + "."),
  ("FDC-00-roadmap.md", 365, "TODO.", "feed %s · groups %s · baseline %s." % (V_feed, V_groups, V_baseline)),
]

by_file = {}
for f, ln, old, new in SLOTS:
    by_file.setdefault(f, []).append((ln, old, new))

applied = mism = 0
for fname, edits in by_file.items():
    path = os.path.join(BASE, fname)
    with open(path, "r") as fh:
        lines = fh.readlines()
    dirty = False
    for ln, old, new in edits:
        idx = ln - 1
        if idx < 0 or idx >= len(lines):
            print("OUT-OF-RANGE %s:%d" % (fname, ln)); mism += 1; continue
        line = lines[idx]
        if old not in line:
            print("MISMATCH    %s:%d  (no %r) :: %s" % (fname, ln, old, line.strip()[:90])); mism += 1; continue
        lines[idx] = line.replace(old, new, 1)
        print("APPLIED     %s:%d  %r -> %r" % (fname, ln, old, new[:48]))
        applied += 1; dirty = True
    if dirty:
        with open(path, "w") as fh:
            fh.writelines(lines)

print("\n=== %d applied, %d mismatch/skipped ===" % (applied, mism))
