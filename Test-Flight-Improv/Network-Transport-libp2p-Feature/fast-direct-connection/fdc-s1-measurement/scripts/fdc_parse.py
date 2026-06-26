#!/usr/bin/env python3
"""FDC-S1 cold-start log parser → median + p90 tables.

Reads one log file per cold trial (Android logcat / iOS syslog dumps), extracts
the FDC instrumentation flow-events, and reports median + p90 per metric per
scenario per device-class. Cold start is heavy-tailed, so we never report mean.

Each device log line carries one JSON payload after a `[FLOW] ` marker (Dart
emitFlowEvent) or is a raw NSE `[FLOW]` NSLog line (iOS). The Go startup_timing /
reservation / circuit events arrive in the same stream re-emitted by the Dart
bridge under layer "GO" (see go_bridge_client._emitRawGoFlowEvent), so the Go
`sinceProcessStartMs` cross-check is captured the same way.

Usage:
  fdc_parse.py --label "pixel6/warm_cold" logs/pixel6_warm_cold_trial_*.log
  fdc_parse.py --label "iphone/notif_tap" --nse logs/iphone_nse_*.log logs/iphone_main_*.log

Each positional arg is ONE trial's log file. The first occurrence of each metric
in a trial is taken (cold-start events are one-shot per launch).
"""
import argparse
import json
import re
import statistics
import sys

FLOW_RE = re.compile(r"\[FLOW\]\s*(\{.*\})\s*$")

# event -> (metric key, details field). Dart-side end-to-end metrics.
DART_METRICS = {
    "FDC_COLDSTART_NODE_START_RETURN_TIMING": ("a_node_start_ms", "sinceProcessStartMs"),
    "FDC_COLDSTART_FIRST_CIRCUIT_TIMING": ("b_first_circuit_ms", "sinceProcessStartMs"),
    "FDC_COLDSTART_FIRST_MDNS_RESOLVE_TIMING": ("c_first_mdns_ms", "sinceProcessStartMs"),
    "FDC_COLDSTART_NOTIF_TAP_NODE_READY": ("d_notif_node_ready_ms", "sinceProcessStartMs"),
}


def parse_flow_lines(path):
    """Yield (layer, event, details) for each [FLOW] json line in a file."""
    with open(path, "r", errors="replace") as f:
        for line in f:
            m = FLOW_RE.search(line)
            if not m:
                continue
            try:
                obj = json.loads(m.group(1))
            except json.JSONDecodeError:
                continue
            yield obj.get("layer"), obj.get("event"), obj.get("details", {})


def first(d, *keys):
    for k in keys:
        if k in d and d[k] is not None:
            return d[k]
    return None


def extract_trial(path):
    """Return a dict of metric -> value (first occurrence) for one trial log."""
    out = {}
    go_sub = {}  # Go sub-phase fields, first occurrence
    for layer, event, details in parse_flow_lines(path):
        if event in DART_METRICS:
            key, field = DART_METRICS[event]
            if key not in out and isinstance(details.get(field), (int, float)):
                out[key] = details[field]
        elif event == "node:startup_timing":
            phase = details.get("phase")
            if phase == "host_ready" and "go_host_ready_ms" not in go_sub:
                go_sub["go_host_ready_ms"] = first(details, "sinceProcessStartMs")
                go_sub["libp2pNewMs"] = first(details, "libp2pNewMs")
                go_sub["pubsubInitMs"] = first(details, "pubsubInitMs")
            elif phase == "relay_warm_done" and "go_relay_warm_done_ms" not in go_sub:
                go_sub["go_relay_warm_done_ms"] = first(details, "sinceProcessStartMs")
                go_sub["relayWarmMs"] = first(details, "relayWarmMs")
        elif event == "relay:reservation_timing":
            if details.get("outcome") == "success" and "go_reserve_ms" not in go_sub:
                go_sub["go_reserve_ms"] = first(details, "sinceProcessStartMs")
                go_sub["reserveRpcMs"] = first(details, "elapsedMs")
        elif event == "circuit_address:timing":
            if details.get("outcome") == "found" and "go_circuit_ms" not in go_sub:
                go_sub["go_circuit_ms"] = first(details, "sinceProcessStartMs")
                go_sub["circuitWaitMs"] = first(details, "elapsedMs")
        elif event == "FDC_RESUME_STEP_TIMING":
            step = details.get("step")
            ms = details.get("ms")
            if step and isinstance(ms, (int, float)):
                out.setdefault("resume_" + step + "_ms", ms)
        elif event == "FDC_NSE_PEERID_AVAILABLE":
            out.setdefault("nse_epoch_ms", first(details, "nseEpochMs"))
            out.setdefault("nse_self_key", details.get("selfKeyPresent"))
            out.setdefault("nse_sender_present", details.get("senderPeerIdPresent"))
            out.setdefault("nse_push_id", details.get("pushId"))
    # absolute epoch for the (d) gap
    for _, event, details in parse_flow_lines(path):
        if event == "FDC_COLDSTART_NOTIF_TAP_NODE_READY":
            out.setdefault("main_epoch_ms", first(details, "epochMs"))
            out.setdefault("main_push_id", first(details, "pushId"))
            break
    out.update(go_sub)
    return out


def pctile(values, q):
    if not values:
        return None
    s = sorted(values)
    if len(s) == 1:
        return s[0]
    # nearest-rank
    import math
    rank = max(0, min(len(s) - 1, math.ceil(q / 100 * len(s)) - 1))
    return s[rank]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--label", default="unlabeled")
    ap.add_argument("--nse", action="store_true",
                    help="also compute G_nse = main_epoch_ms - nse_epoch_ms matched by pushId across the given files")
    ap.add_argument("files", nargs="+")
    args = ap.parse_args()

    trials = []
    nse_epochs = {}   # pushId -> nseEpochMs
    main_epochs = {}  # pushId -> mainEpochMs
    for path in args.files:
        t = extract_trial(path)
        t["_file"] = path
        trials.append(t)
        if t.get("nse_push_id") and t.get("nse_epoch_ms"):
            try:
                nse_epochs[t["nse_push_id"]] = int(t["nse_epoch_ms"])
            except (ValueError, TypeError):
                pass
        if t.get("main_push_id") and t.get("main_epoch_ms"):
            main_epochs[t["main_push_id"]] = t["main_epoch_ms"]

    # collect numeric metrics
    metric_keys = []
    for t in trials:
        for k, v in t.items():
            if k.startswith("_"):
                continue
            if isinstance(v, (int, float)) and k not in metric_keys:
                metric_keys.append(k)

    print(f"\n=== FDC-S1 results: {args.label}  (n={len(trials)} trials) ===")
    print(f"{'metric':<28} {'n':>3} {'min':>7} {'median':>8} {'p90':>7} {'max':>7}")
    print("-" * 64)
    order = ["a_node_start_ms", "go_host_ready_ms", "libp2pNewMs", "pubsubInitMs",
             "go_relay_warm_done_ms", "relayWarmMs", "go_reserve_ms", "reserveRpcMs",
             "b_first_circuit_ms", "go_circuit_ms", "circuitWaitMs",
             "c_first_mdns_ms", "d_notif_node_ready_ms"]
    ordered = [k for k in order if k in metric_keys] + [k for k in metric_keys if k not in order]
    for k in ordered:
        vals = [t[k] for t in trials if isinstance(t.get(k), (int, float)) and t[k] >= 0]
        if not vals:
            continue
        med = statistics.median(vals)
        print(f"{k:<28} {len(vals):>3} {min(vals):>7.0f} {med:>8.0f} "
              f"{pctile(vals, 90):>7.0f} {max(vals):>7.0f}")

    if args.nse:
        print("\n--- (d) NSE→main gap G_nse (matched by pushId) ---")
        gaps = []
        for pid, nse in nse_epochs.items():
            if pid in main_epochs:
                gap = main_epochs[pid] - nse
                gaps.append(gap)
                print(f"  pushId={pid[:16]:<16} G_nse={gap}ms")
        if gaps:
            print(f"  G_nse median={statistics.median(gaps):.0f}ms p90={pctile(gaps,90):.0f}ms (n={len(gaps)})")
        else:
            print("  no matched pushIds (need NSE + main logs from the SAME cold notif-tap)")

    # raw dump for the record
    print("\n--- raw per-trial ---")
    for t in trials:
        row = {k: v for k, v in t.items() if not k.startswith("_")}
        print(f"  {t['_file'].split('/')[-1]}: {json.dumps(row)}")


if __name__ == "__main__":
    sys.exit(main())
