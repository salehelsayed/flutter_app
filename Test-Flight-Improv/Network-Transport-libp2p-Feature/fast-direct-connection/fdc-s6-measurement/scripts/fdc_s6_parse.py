#!/usr/bin/env python3
"""FDC-S6 libp2p-LAN soak log parser.

Reads device capture logs (from fdc_s6_capture.sh) and computes the per-
platform-direction numbers the FDC-S6 Decision Criteria need:

  - libp2p-LAN win-rate, with a Wilson score 95% LOWER bound (the retire-chat
    headline: gate is LB >= 95% over n >= 385 same-WiFi sends).
  - WS-LAN ('wifi') win share + the full per-transport receive census.
  - bonsoir-fed-dial reliability (direct wins to a bonsoir-fed peer / sends to it).
  - double-delivery rate, keyed by the (kept, dropped) transport-leg pair.
  - failure-rate, and (with --baseline-file) the Newcombe 95% CI on
    [failureRate(ON) - failureRate(baseline)] for the <= +1.0pp non-inferiority
    bar.

The authoritative logical outcome per same-WiFi send is read from the
receiver-side `CHAT_MSG_RECEIVE_STORED` flow-event ({id, from, transport},
handle_incoming_chat_message_use_case.dart). Raw `MSG_RECEIVED_TRANSPORT`
events remain the arrival-leg census used to audit parallel delivery. A clean
libp2p-LAN win = a stored `direct` outcome whose peer was bonsoir-fed
(P2P_LAN_PEER_FOUND_REQUEST fired) AND private-IP (lanPrivateIp:true, the FDC-S6
net-new Dart discriminator), EXCLUDING `reuse`/`upgraded` (DCUtR/conn-reuse folds,
not a fresh LAN dial). A bare `direct` without those guards is AMBIGUOUS
(could be WAN/DCUtR) and is NOT counted as a LAN win — see the spike's ⚠ caveat.

No third-party deps. Usage:
    python3 fdc_s6_parse.py --label androidA->androidB logs/aa/*.log
    python3 fdc_s6_parse.py --label iA->iB --baseline-file logs/baseline/*.log logs/on/*.log
"""
import argparse
import json
import math
import re
import sys

FLOW_JSON_RE = re.compile(r"\[FLOW\]\s*(\{.*\})\s*$")

WIN_EVENT = "MSG_RECEIVED_TRANSPORT"
STORED_EVENT = "CHAT_MSG_RECEIVE_STORED"
LAN_FOUND_EVENT = "P2P_LAN_PEER_FOUND_REQUEST"
DOUBLE_DELIVERY_EVENT = "CHAT_MSG_DOUBLE_DELIVERY"

# Transports that are a delivered LEG (a same-WiFi send arrived over it).
DELIVERED_LEGS = {"wifi", "direct", "relay", "inbox", "reuse", "upgraded", "unknown"}
# Folds that are NOT a fresh libp2p-LAN dial (DCUtR upgrade / conn reuse).
EXCLUDED_FROM_LAN_WIN = {"reuse", "upgraded"}
# Legs that did not deliver successfully (count toward the failure-rate delta).
FAILURE_LEGS = {"inbox"}  # inbox = no live leg won; the send fell to the durable inbox


def wilson_lb(k, n, z=1.96):
    """Wilson score lower bound for k successes in n trials."""
    if n < 0 or k < 0 or k > n:
        raise ValueError(f"successes must be between 0 and n (got k={k}, n={n})")
    if n == 0:
        return None
    phat = k / n
    denom = 1 + z * z / n
    centre = phat + z * z / (2 * n)
    margin = z * math.sqrt((phat * (1 - phat) + z * z / (4 * n)) / n)
    return max(0.0, (centre - margin) / denom)


def wilson_interval(k, n, z=1.96):
    if n < 0 or k < 0 or k > n:
        raise ValueError(f"successes must be between 0 and n (got k={k}, n={n})")
    if n == 0:
        return (None, None)
    phat = k / n
    denom = 1 + z * z / n
    centre = phat + z * z / (2 * n)
    margin = z * math.sqrt((phat * (1 - phat) + z * z / (4 * n)) / n)
    return (max(0.0, (centre - margin) / denom), min(1.0, (centre + margin) / denom))


def newcombe_diff_ci(k1, n1, k2, n2, z=1.96):
    """Newcombe (Wilson-based) CI for p1 - p2. Returns (lower, upper) or None."""
    if n1 == 0 or n2 == 0:
        return None
    p1, p2 = k1 / n1, k2 / n2
    l1, u1 = wilson_interval(k1, n1, z)
    l2, u2 = wilson_interval(k2, n2, z)
    d = p1 - p2
    lower = d - math.sqrt((p1 - l1) ** 2 + (u2 - p2) ** 2)
    upper = d + math.sqrt((u1 - p1) ** 2 + (p2 - l2) ** 2)
    return (lower, upper)


def parse_files(paths):
    """Returns the raw tallies for one arm (a set of trial logs)."""
    sends = []            # list of (peer_prefix, transport) per MSG_RECEIVED_TRANSPORT
    stored = []           # list of (peer_prefix, kept transport) per logical message
    bonsoir_peers = set()  # peers a P2P_LAN_PEER_FOUND_REQUEST fired for
    private_ip_peers = set()  # subset with lanPrivateIp:true
    double_deliveries = []  # list of (kept, dropped)
    bad_lines = 0

    for path in paths:
        try:
            with open(path, "r", errors="replace") as fh:
                lines = fh.readlines()
        except OSError as e:
            print(f"  ! skip {path}: {e}", file=sys.stderr)
            continue
        for line in lines:
            m = FLOW_JSON_RE.search(line)
            if not m:
                continue
            try:
                payload = json.loads(m.group(1))
            except json.JSONDecodeError:
                bad_lines += 1
                continue
            event = payload.get("event", "")
            details = payload.get("details", {}) or {}
            if event == WIN_EVENT:
                t = (details.get("transport") or "unknown").lower()
                # Peer prefixes join the win leg to its LAN-discovery row. Both
                # come from the same peerId.substring(0,10); strip whitespace to
                # harden the join, but NEVER lowercase — peer IDs are base58
                # (case-sensitive), so folding case could collide distinct IDs.
                sends.append(((details.get("from") or "").strip(), t))
            elif event == STORED_EVENT:
                stored.append(
                    (
                        (details.get("from") or "").strip(),
                        (details.get("transport") or "unknown").strip().lower(),
                    )
                )
            elif event == LAN_FOUND_EVENT:
                peer = (details.get("peer") or "").strip()
                if peer:
                    bonsoir_peers.add(peer)
                    if details.get("lanPrivateIp") is True:
                        private_ip_peers.add(peer)
            elif event == DOUBLE_DELIVERY_EVENT:
                double_deliveries.append(
                    (details.get("kept"), details.get("dropped"))
                )
    return dict(
        sends=sends,
        stored=stored,
        bonsoir_peers=bonsoir_peers,
        private_ip_peers=private_ip_peers,
        double_deliveries=double_deliveries,
        bad_lines=bad_lines,
    )


def classify(raw):
    """Derive the FDC-S6 metrics from one arm's raw tallies.

    Current logs carry one CHAT_MSG_RECEIVE_STORED event per logical send, with
    the kept transport. Legacy pilot logs are retained through a conservative
    per-file fallback because staged inbox replay does not itself emit the raw
    MSG_RECEIVED_TRANSPORT arrival event.
    """
    sends = raw["sends"]
    stored = raw["stored"]
    bonsoir = raw["bonsoir_peers"]
    private_ip = raw["private_ip_peers"]

    n_legs = len(sends)
    census = {}
    lan_wins = 0           # clean bonsoir-fed + private-IP + non-fold 'direct'
    ws_wins = 0            # 'wifi'
    ambiguous_direct = 0   # 'direct' without bonsoir-fed + private-IP guards
    excluded_folds = 0     # 'reuse' / 'upgraded'
    failures = 0           # inbox (no live leg won)
    bonsoir_fed_sends = 0  # logical sends to a bonsoir-fed peer

    # Raw arrival census only. Decision metrics below use the authoritative
    # logical outcome when that current-format event is present.
    for _peer, t in sends:
        census[t] = census.get(t, 0) + 1

    dd = raw["double_deliveries"]
    if stored:
        # Current-format logs: every stored row is exactly one logical send.
        for peer, t in stored:
            if peer in bonsoir:
                bonsoir_fed_sends += 1
            if t == "wifi":
                ws_wins += 1
            elif t in EXCLUDED_FROM_LAN_WIN:
                excluded_folds += 1
            elif t == "direct":
                if peer in bonsoir and peer in private_ip:
                    lan_wins += 1
                else:
                    ambiguous_direct += 1
            if t in FAILURE_LEGS:
                failures += 1
        n = len(stored)
    else:
        # Legacy pilot fallback. classify_paths invokes this once per file, so
        # a later trial's private-IP discovery cannot reclassify an older trial.
        for peer, t in sends:
            if peer in bonsoir:
                bonsoir_fed_sends += 1
            if t == "wifi":
                ws_wins += 1
            elif t in EXCLUDED_FROM_LAN_WIN:
                excluded_folds += 1
            elif t == "direct":
                if peer in bonsoir and peer in private_ip:
                    lan_wins += 1
                else:
                    ambiguous_direct += 1
            if t in FAILURE_LEGS:
                failures += 1

        n = n_legs
        for kept, dropped in dd:
            d = (dropped or "").strip().lower()
            # Live dropped legs are present in the raw arrival census. Staged
            # inbox replay bypasses that event, so a dropped inbox is absent
            # already and must not shrink the denominator.
            if d in DELIVERED_LEGS and d != "inbox":
                n = max(0, n - 1)
                if d == "wifi":
                    ws_wins = max(0, ws_wins - 1)
                elif d == "direct":
                    if lan_wins > 0:
                        lan_wins -= 1
                    else:
                        ambiguous_direct = max(0, ambiguous_direct - 1)
                elif d in EXCLUDED_FROM_LAN_WIN:
                    excluded_folds = max(0, excluded_folds - 1)
                elif d in FAILURE_LEGS:
                    failures = max(0, failures - 1)
                bonsoir_fed_sends = max(0, bonsoir_fed_sends - 1)

            # If inbox committed first, synthesize its otherwise-unlogged
            # logical outcome after removing any represented dropped live leg.
            k = (kept or "").strip().lower()
            if k == "inbox":
                n += 1
                failures += 1
                if bonsoir:
                    bonsoir_fed_sends += 1

    return dict(
        n=n,
        n_legs=n_legs,
        census=census,
        lan_wins=lan_wins,
        ws_wins=ws_wins,
        ambiguous_direct=ambiguous_direct,
        excluded_folds=excluded_folds,
        failures=failures,
        bonsoir_fed_sends=bonsoir_fed_sends,
        double_deliveries=dd,
        bad_lines=raw["bad_lines"],
    )


def merge_classified(classified):
    """Sum independently classified trial files without leaking peer evidence."""
    merged = dict(
        n=0,
        n_legs=0,
        census={},
        lan_wins=0,
        ws_wins=0,
        ambiguous_direct=0,
        excluded_folds=0,
        failures=0,
        bonsoir_fed_sends=0,
        double_deliveries=[],
        bad_lines=0,
    )
    for current in classified:
        for key in (
            "n",
            "n_legs",
            "lan_wins",
            "ws_wins",
            "ambiguous_direct",
            "excluded_folds",
            "failures",
            "bonsoir_fed_sends",
            "bad_lines",
        ):
            merged[key] += current[key]
        for transport, count in current["census"].items():
            merged["census"][transport] = merged["census"].get(transport, 0) + count
        merged["double_deliveries"].extend(current["double_deliveries"])
    return merged


def classify_paths(paths):
    return merge_classified(classify(parse_files([path])) for path in paths)


def pct(x):
    return "—" if x is None else f"{100.0 * x:.1f}%"


SAMPLE_FLOOR = 385  # >= 385 sends/platform-direction (≈ ±5pp at 95% conf)


def report(label, c, baseline=None):
    n = c["n"]
    print(f"\n=== FDC-S6 libp2p-LAN soak — {label} ===")
    n_dd = len(c["double_deliveries"])
    print(f"\n[sample floor]  logical sends n={n}  (raw delivery legs={c['n_legs']}, "
          f"double-delivery collisions={n_dd})  "
          f"({'OK' if n >= SAMPLE_FLOOR else f'BELOW {SAMPLE_FLOOR} — UNDERPOWERED'})")
    if c["bad_lines"]:
        print(f"  ! {c['bad_lines']} unparseable [FLOW] lines skipped")

    print("\n[transport census]  (raw MSG_RECEIVED_TRANSPORT delivery legs; reuse/")
    print("                     upgraded kept DISTINCT to exclude from LAN wins)")
    for t in sorted(c["census"]):
        print(f"  {t:9s} {c['census'][t]}")

    print("\n[libp2p-LAN win-rate]  (Decision Criterion: Wilson 95% LB >= 95%)")
    lb = wilson_lb(c["lan_wins"], n)
    phat = (c["lan_wins"] / n) if n else None
    print(f"  clean LAN wins (bonsoir-fed + private-IP + non-fold direct) = {c['lan_wins']}/{n}")
    print(f"  point estimate = {pct(phat)}   Wilson 95% LB = {pct(lb)}"
          + ("  ✅ >= 95%" if lb is not None and lb >= 0.95 else "  ❌ < 95% (KEEP WS)"))
    print(f"  ambiguous 'direct' (WAN/DCUtR — NOT counted as LAN win) = {c['ambiguous_direct']}")
    print(f"  excluded folds (reuse/upgraded) = {c['excluded_folds']}")
    print(f"  WS 'wifi' wins = {c['ws_wins']}")

    print("\n[bonsoir-fed dial reliability]  (Wilson 95% LB >= 95%)")
    bn, bk = c["bonsoir_fed_sends"], c["lan_wins"]
    blb = wilson_lb(bk, bn)
    print(f"  clean LAN wins / sends-to-bonsoir-fed-peer = {bk}/{bn}"
          f"   Wilson 95% LB = {pct(blb)}")

    print("\n[double-delivery]  (parallel-run cost, keyed by (kept, dropped) leg pair)")
    dd = c["double_deliveries"]
    pair_counts = {}
    for kept, dropped in dd:
        key = f"{kept or 'null'}+{dropped or 'null'}"
        pair_counts[key] = pair_counts.get(key, 0) + 1
    dd_rate = (len(dd) / n) if n else None
    print(f"  total collisions = {len(dd)}   rate = {pct(dd_rate)} of logical sends")
    for key in sorted(pair_counts):
        print(f"    {key:18s} {pair_counts[key]}")

    print("\n[failure rate]  (non-inferiority vs WS baseline; gate = diff upper 95% CI <= +1.0pp)")
    f_rate = (c["failures"] / n) if n else None
    print(f"  failures (inbox fallback, no live leg) = {c['failures']}/{n}   rate = {pct(f_rate)}")
    if baseline is not None:
        bn2, bf = baseline["n"], baseline["failures"]
        print(f"  baseline (WS arm) failures = {bf}/{bn2}   rate = {pct((bf/bn2) if bn2 else None)}")
        ci = newcombe_diff_ci(c["failures"], n, bf, bn2)
        if ci is not None:
            lo, hi = ci
            ok = hi <= 0.01
            print(f"  Newcombe 95% CI on [ON - baseline] = "
                  f"[{100*lo:+.2f}pp, {100*hi:+.2f}pp]"
                  + ("  ✅ <= +1.0pp" if ok else "  ❌ > +1.0pp (KEEP WS)"))
    print()


def main():
    ap = argparse.ArgumentParser(description="Parse FDC-S6 libp2p-LAN soak logs.")
    ap.add_argument("--label", default="trial",
                    help="platform-direction, e.g. androidA->androidB / iA->iB / A<->i")
    ap.add_argument("--baseline-file", nargs="*", default=None,
                    help="WS-baseline-arm logs for the failure-delta non-inferiority CI")
    ap.add_argument("logs", nargs="+")
    args = ap.parse_args()

    arm = classify_paths(args.logs)
    baseline = None
    if args.baseline_file:
        baseline = classify_paths(args.baseline_file)
    report(args.label, arm, baseline)


if __name__ == "__main__":
    main()
