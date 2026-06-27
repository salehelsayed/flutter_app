#!/usr/bin/env python3
"""FDC-S4 pause-flush log parser.

Reads tethered-iPhone capture logs (from fdc_s4_capture.sh) and reports the
numbers the spike Exit Gate needs:

  - granted OS background budget  (native BG_TASK_GRANTED backgroundTimeRemainingSec)
  - per-message deposit ms        (APP_LIFECYCLE_PAUSE_FLUSH_DEPOSIT.details.ms)
  - total flush ms                (APP_LIFECYCLE_PAUSE_FLUSH_COMPLETE.details.totalMs)
  - expired rate / BG_TASK_EXPIRED / BG_TASK_REFUSED
  - deposit success rate
  - N (in-flight sending count) distribution -> median + p95 to size the cap

No third-party deps. Usage:
    python3 fdc_s4_parse.py --label iphone/n1 logs/iphone/n1/*.log
"""
import argparse
import json
import re
import sys

# backgroundTimeRemaining can be .greatestFiniteMagnitude before the app is fully
# backgrounded; treat anything above this as "unbounded" and exclude from stats.
UNBOUNDED_SEC = 1_000_000.0

GRANT_RE = re.compile(r"backgroundTimeRemainingSec=([0-9eE.+-]+|inf|nan)")
FLOW_JSON_RE = re.compile(r"\[FLOW\]\s*(\{.*\})\s*$")


def median(xs):
    if not xs:
        return None
    s = sorted(xs)
    n = len(s)
    mid = n // 2
    return s[mid] if n % 2 else (s[mid - 1] + s[mid]) / 2.0


def pct(xs, p):
    if not xs:
        return None
    s = sorted(xs)
    # nearest-rank
    k = max(0, min(len(s) - 1, int(round((p / 100.0) * (len(s) - 1)))))
    return s[k]


def parse_files(paths):
    grants = []          # float seconds (bounded only)
    unbounded_grants = 0
    expired_native = 0
    refused_native = 0
    deposit_ms = []      # per-message ms
    deposit_ok = 0
    deposit_total = 0
    total_ms = []        # per-flush totalMs
    expired_flush = 0
    flush_count = 0
    n_values = []        # sendingCount per BEGIN
    deposited_counts = []
    skipped_counts = []

    for path in paths:
        try:
            with open(path, "r", errors="replace") as fh:
                lines = fh.readlines()
        except OSError as e:
            print(f"  ! skip {path}: {e}", file=sys.stderr)
            continue

        for line in lines:
            if "BG_TASK_GRANTED" in line or "BG_GRANT_PROBE" in line:
                m = GRANT_RE.search(line)
                if m:
                    try:
                        v = float(m.group(1))
                        if v >= UNBOUNDED_SEC or v != v:  # nan
                            unbounded_grants += 1
                        else:
                            grants.append(v)
                    except ValueError:
                        unbounded_grants += 1
                continue
            if "BG_TASK_EXPIRED" in line:
                expired_native += 1
                continue
            if "BG_TASK_REFUSED" in line:
                refused_native += 1
                continue

            m = FLOW_JSON_RE.search(line)
            if not m:
                continue
            try:
                payload = json.loads(m.group(1))
            except json.JSONDecodeError:
                continue
            event = payload.get("event", "")
            details = payload.get("details", {}) or {}
            if event == "APP_LIFECYCLE_PAUSE_GRANT_PROBE":
                # FDC-S4: the grant value rides the reliable Flutter [FLOW]
                # channel (native os_log buffers during true suspension).
                gv = details.get("grantSec")
                if isinstance(gv, (int, float)):
                    if gv >= UNBOUNDED_SEC or gv != gv:
                        unbounded_grants += 1
                    else:
                        grants.append(float(gv))
            elif event == "APP_LIFECYCLE_PAUSE_FLUSH_BEGIN":
                if isinstance(details.get("sendingCount"), int):
                    n_values.append(details["sendingCount"])
            elif event == "APP_LIFECYCLE_PAUSE_FLUSH_DEPOSIT":
                deposit_total += 1
                if details.get("ok") is True:
                    deposit_ok += 1
                if isinstance(details.get("ms"), (int, float)):
                    deposit_ms.append(details["ms"])
            elif event == "APP_LIFECYCLE_PAUSE_FLUSH_COMPLETE":
                flush_count += 1
                if isinstance(details.get("totalMs"), (int, float)):
                    total_ms.append(details["totalMs"])
                if details.get("expired") is True:
                    expired_flush += 1
                if isinstance(details.get("deposited"), int):
                    deposited_counts.append(details["deposited"])
                if isinstance(details.get("skipped"), int):
                    skipped_counts.append(details["skipped"])

    return dict(
        grants=grants, unbounded_grants=unbounded_grants,
        expired_native=expired_native, refused_native=refused_native,
        deposit_ms=deposit_ms, deposit_ok=deposit_ok, deposit_total=deposit_total,
        total_ms=total_ms, expired_flush=expired_flush, flush_count=flush_count,
        n_values=n_values, deposited_counts=deposited_counts,
        skipped_counts=skipped_counts,
    )


def fmt(v, unit=""):
    if v is None:
        return "—"
    if isinstance(v, float):
        return f"{v:.1f}{unit}"
    return f"{v}{unit}"


def report(label, r):
    print(f"\n=== FDC-S4 pause-flush — {label} ===")

    print("\n[grant] OS background budget after bgBegin (Decision Criterion 1: >= ~25s)")
    g = r["grants"]
    print(f"  n={len(g)} (+{r['unbounded_grants']} unbounded/pre-background)"
          f"  min={fmt(min(g) if g else None,'s')}"
          f"  median={fmt(median(g),'s')}  p90={fmt(pct(g,90),'s')}")
    if g and median(g) is not None and median(g) < 25:
        print("  ⚠ median grant < 25s — tighten ceiling/cap or reconsider Option B (spike Decision Criteria).")

    print("\n[per-deposit ms]  storeInInbox round-trip")
    d = r["deposit_ms"]
    print(f"  n={len(d)}  median={fmt(median(d),'ms')}  p90={fmt(pct(d,90),'ms')}"
          f"  max={fmt(max(d) if d else None,'ms')}")

    print("\n[total flush ms]  (Exit Gate: < 8000ms ceiling in >=95% of trials)")
    t = r["total_ms"]
    over = [x for x in t if x > 8000]
    print(f"  flushes={r['flush_count']}  median={fmt(median(t),'ms')}  p90={fmt(pct(t,90),'ms')}"
          f"  over-8s={len(over)}/{len(t)}")

    print("\n[termination safety]")
    print(f"  BG_TASK_EXPIRED (benign, expected on hung net) = {r['expired_native']}")
    print(f"  flush expired:true = {r['expired_flush']}")
    print(f"  BG_TASK_REFUSED = {r['refused_native']}")
    print("  (app TERMINATION cannot appear in-log — confirm the process survived each trial.)")

    print("\n[deposit success]")
    tot = r["deposit_total"]
    rate = (100.0 * r["deposit_ok"] / tot) if tot else None
    print(f"  ok={r['deposit_ok']}/{tot}  rate={fmt(rate,'%') if rate is not None else '—'}"
          f"  deposited-per-flush={r['deposited_counts']}  skipped-per-flush={r['skipped_counts']}")

    print("\n[N distribution]  in-flight sending count at pause (Exit Gate 2: cap = p95)")
    n = r["n_values"]
    print(f"  values={sorted(n)}  median={fmt(median(n))}  p95={fmt(pct(n,95))}")
    if n and pct(n, 95) is not None:
        print(f"  → suggested cap = max(1, p95) = {max(1, pct(n,95))} (default plan = 5)")
    print()


def main():
    ap = argparse.ArgumentParser(description="Parse FDC-S4 pause-flush device logs.")
    ap.add_argument("--label", default="trial")
    ap.add_argument("logs", nargs="+")
    args = ap.parse_args()
    report(args.label, parse_files(args.logs))


if __name__ == "__main__":
    main()
