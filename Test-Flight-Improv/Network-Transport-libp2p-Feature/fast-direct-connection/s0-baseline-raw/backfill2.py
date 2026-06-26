#!/usr/bin/env python3
"""FDC-S0 back-fill PASS 2 — additional command-line gate slots the strict
`expected:` enumerator missed (variant phrasing: `expect: ok (TODO count)`,
`# TODO expected count`, `expected pass count:`, `+TODO`). Same verified
line-number + exact-token replacement as pass 1. core-host-all / feature-host-all
count slots are handled in pass 3 (core-host still running; feature-host is
covered transitively by 1to1/feed/groups)."""
import os

BASE = "/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Network-Transport-libp2p-Feature/fast-direct-connection"
V_1to1 = "1226"; V_transp = "device/fixture-gated (skips on lone sim)"
V_gorelay = "191 pass / 0 fail / 2 skip"
V_gomknoon = "all pkgs PASS (go1.25.0, ~1171 tests)"

SLOTS = [
  ("FDC-03-concurrent-durable-inbox-safety-net-tdd-plan.md", 277, "TODO.", V_transp + "."),
  ("FDC-04-lan-aware-eager-warmpeer-tdd-plan.md", 349, "TODO", V_1to1),

  ("FDC-08-relay-presence-lookup-tdd-plan.md", 448, "TODO count", V_gorelay),
  ("FDC-08-relay-presence-lookup-tdd-plan.md", 452, "TODO count", V_gomknoon),
  ("FDC-08-relay-presence-lookup-tdd-plan.md", 456, "+TODO", "1226 baseline +N"),
  ("FDC-08-relay-presence-lookup-tdd-plan.md", 458, "(TODO)", "(device/fixture-gated; skips on lone sim)"),

  ("FDC-11-libp2p-mdns-host-tdd-plan.md", 494, "TODO expected count", "expected count: go1.25.0 all-pass (~1171 baseline)"),
  ("FDC-11-libp2p-mdns-host-tdd-plan.md", 502, "TODO expected counts", "expected: device/fixture-gated baseline (skips on lone sim)"),

  ("FDC-12-dcutr-relay-direct-upgrade-tdd-plan.md", 437, "TODO baseline+new", "go1.25.0 all-pass baseline +new"),
  ("FDC-12-dcutr-relay-direct-upgrade-tdd-plan.md", 441, "TODO count", "1226 baseline"),
  ("FDC-12-dcutr-relay-direct-upgrade-tdd-plan.md", 442, "TODO count", V_transp),

  ("FDC-13-relay-direct-upgraded-badge-tdd-plan.md", 184, "TODO: capture baseline (prior ~1226)", "baseline 1226 (FDC-S0)"),

  ("FDC-14-online-dot-directly-reachable-tdd-plan.md", 387, "TODO: prior ~1226", "1226 baseline, FDC-S0"),
]

by_file = {}
for f, ln, old, new in SLOTS:
    by_file.setdefault(f, []).append((ln, old, new))

applied = mism = 0
for fname, edits in by_file.items():
    path = os.path.join(BASE, fname)
    with open(path) as fh:
        lines = fh.readlines()
    dirty = False
    for ln, old, new in edits:
        idx = ln - 1
        if not (0 <= idx < len(lines)):
            print("OUT-OF-RANGE %s:%d" % (fname, ln)); mism += 1; continue
        if old not in lines[idx]:
            print("MISMATCH    %s:%d (no %r) :: %s" % (fname, ln, old, lines[idx].strip()[:90])); mism += 1; continue
        lines[idx] = lines[idx].replace(old, new, 1)
        print("APPLIED     %s:%d  %r -> %r" % (fname, ln, old, new[:46])); applied += 1; dirty = True
    if dirty:
        with open(path, "w") as fh:
            fh.writelines(lines)

print("\n=== pass2: %d applied, %d mismatch ===" % (applied, mism))
