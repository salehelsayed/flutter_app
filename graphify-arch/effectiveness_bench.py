#!/usr/bin/env python3
"""Head-to-head: graphify compact query vs raw grep/read, same questions.

Tokens = chars/4 (same approximation the repo's own ledger uses).
Tool output is capped at 30_000 chars (harness truncation), so a raw grep
that overflows costs ~7.5k tokens AND loses data (flagged as truncated).
File reads model the Read tool: first 2000 lines, `cat -n` style prefix.
"""
import json, os, re, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("effectiveness_bench_results.json")
CAP = 30_000
READ_LINES = 2000
ENV = dict(os.environ, GRAPH_OK="1")
SRC = ["lib", "test", "integration_test"]


def tok(s):
    return len(s) // 4


def sh(cmd, cwd=ROOT):
    t = time.time()
    p = subprocess.run(cmd, cwd=cwd, env=ENV, capture_output=True, text=True)
    return p.stdout + p.stderr, time.time() - t


def capped(s):
    return (s[:CAP], True) if len(s) > CAP else (s, False)


def read_cost(path, lines=READ_LINES):
    """Tokens the Read tool would inject for this file."""
    try:
        txt = (ROOT / path).read_text(errors="replace").splitlines()[:lines]
    except FileNotFoundError:
        return 0
    return tok("\n".join(f"{i+1:6d}\t{l}" for i, l in enumerate(txt)))


def files_in(text):
    """Every repo-relative source path mentioned in a blob of text."""
    return set(re.findall(r"(?:lib|test|integration_test|go-mknoon|android/app/src/main)/[\w./-]+\.(?:dart|go|kt|swift)", text))


def graph(q, profile, budget, op="query", extra=()):
    if op == "affected":
        cmd = ["python3", "graphify-arch/tdd_context.py", "affected", *q, "--budget", str(budget)]
    else:
        cmd = ["python3", "graphify-arch/tdd_context.py", "query", q, "--profile", profile, "--budget", str(budget), *extra]
    out, dt = sh(cmd)
    hdr = out.splitlines()[0] if out else ""
    meta = dict(re.findall(r"(\w+)=([^\s]+)", hdr))
    return dict(out=out, tokens=tok(out), secs=round(dt, 2), files=files_in(out),
                confidence=meta.get("confidence"), freshness=meta.get("freshness"),
                truncated="truncated at ~" in out)


def rg(*args):
    out, dt = sh(["rg", *args])
    out, trunc = capped(out)
    return dict(out=out, tokens=tok(out), secs=round(dt, 2), files=files_in(out), truncated=trunc)


def gt_users(sym, deffile):
    out, _ = sh(["rg", "-l", "-w", sym, *SRC])
    return set(out.split()) - {deffile}


def gt_tests(libfile):
    out, _ = sh(["rg", "-l", Path(libfile).name, "test", "integration_test"])
    return set(out.split())


results = []

# ---------- 1. define: where is X defined ----------
DEFS = [
    ("BridgeCallIceServerProvider", "lib/features/call/infrastructure/bridge_call_ice_server_provider.dart"),
    ("CallAudioNegotiationPreparer", "lib/features/call/application/call_audio_negotiation_preparer.dart"),
    ("CallNegotiationEffectExecutor", "lib/features/call/application/call_negotiation_effect_executor.dart"),
    ("FlutterWebRtcCallEngine", "lib/features/call/infrastructure/flutter_webrtc_call_engine.dart"),
    ("CallRingbackCoordinator", "lib/features/call/application/call_ringback_coordinator.dart"),
    ("callP2PTurnCredentialsV1", "lib/core/bridge/p2p_bridge_client.dart"),
]
for sym, deffile in DEFS:
    gt_line_out, _ = sh(["rg", "-n", "-w", sym, deffile])
    gt_line = next((int(l.split(":")[0]) for l in gt_line_out.splitlines()
                    if re.search(r"\b(class|Future<[^>]*>|void|\w+)\s+" + sym + r"\b", l) and "import" not in l), None)
    g = graph(sym, "general", 600)
    g_line = None
    m = re.search(re.escape(deffile) + r":(\d+)", g["out"])
    if m:
        g_line = int(m.group(1))
    # raw-min: an expert who knows it is a class/function and greps the definition only
    r_min = rg("-n", "-w", sym, "lib", "--glob", "*.dart", "-e", f"class {sym}", "-e", f" {sym}(")
    # raw-typical: symbol grep across lib/test/integration_test, then Read the def file
    r_typ = rg("-n", "-w", sym, *SRC)
    r_typ_total = r_typ["tokens"] + read_cost(deffile)
    results.append(dict(kind="define", q=sym, gt={"file": deffile, "line": gt_line},
        graph=dict(tokens=g["tokens"], secs=g["secs"], hit=deffile in g["files"], line=g_line,
                   line_exact=(g_line == gt_line), confidence=g["confidence"], freshness=g["freshness"]),
        raw_min=dict(tokens=r_min["tokens"], secs=r_min["secs"], hit=deffile in r_min["files"], truncated=r_min["truncated"]),
        raw_typical=dict(tokens=r_typ_total, grep_tokens=r_typ["tokens"], secs=r_typ["secs"],
                         hit=deffile in r_typ["files"], truncated=r_typ["truncated"])))

# ---------- 2. dependents: who uses X ----------
for sym, deffile in DEFS[:5]:
    gt = gt_users(sym, deffile)
    g = graph(sym, "review", 800)
    found = (g["files"] & gt)
    r = rg("-l", "-w", sym, *SRC)
    r_found = r["files"] & gt
    results.append(dict(kind="dependents", q=sym, gt=sorted(gt), gt_n=len(gt),
        graph=dict(tokens=g["tokens"], secs=g["secs"], recall=round(len(found) / max(1, len(gt)), 2),
                   found=len(found), extra=len(g["files"] - gt - {deffile}), confidence=g["confidence"], truncated=g["truncated"]),
        raw_min=dict(tokens=r["tokens"], secs=r["secs"], recall=round(len(r_found) / max(1, len(gt)), 2), found=len(r_found))))

# ---------- 3. tests-for-file ----------
TESTF = [
    "lib/features/call/infrastructure/bridge_call_ice_server_provider.dart",
    "lib/features/call/application/call_negotiation_effect_executor.dart",
    "lib/features/call/application/call_ringback_coordinator.dart",
]
for f in TESTF:
    gt = gt_tests(f)
    g = graph(f, "tdd", 700)
    found = g["files"] & gt
    r = rg("-l", Path(f).name, "test", "integration_test")
    results.append(dict(kind="tests_for_file", q=f, gt_n=len(gt), gt=sorted(gt),
        graph=dict(tokens=g["tokens"], secs=g["secs"], recall=round(len(found) / max(1, len(gt)), 2), found=len(found),
                   confidence=g["confidence"], truncated=g["truncated"]),
        raw_min=dict(tokens=r["tokens"], secs=r["secs"], recall=round(len(r["files"] & gt) / max(1, len(gt)), 2))))

# ---------- 4. natural language (no symbol known) ----------
NL = [
    ("how is the caller-side ringback tone started and stopped",
     ["ringback", "tone", "caller"], {"lib/features/call/application/call_ringback_coordinator.dart"}),
    ("where does the app fetch TURN credentials from the Go bridge",
     ["turn", "credentials", "bridge"], {"lib/core/bridge/p2p_bridge_client.dart", "lib/features/call/infrastructure/bridge_call_ice_server_provider.dart"}),
    ("android killed app call decline reply headless",
     ["decline", "reply", "headless"], {"lib/features/call/application/headless_call_decline_reply.dart"}),
    ("terminal call rows rendered in the 1:1 chat history",
     ["call", "history", "terminal", "projector"], {"lib/features/call/application/call_history_projector.dart"}),
]
for q, kws, gt in NL:
    g = graph(q, "general", 600)
    g_hit = bool(g["files"] & gt)
    # refine-once protocol from CLAUDE.md: if broad, re-query with the first 'Did you mean' / anchor the output suggests
    refine = None
    if not g_hit or g["confidence"] != "anchored":
        m = re.search(r"Did you mean:?\s*(.+)", g["out"]) or re.search(r"- ([A-Za-z_][\w]+) — (?:lib|test)/", g["out"])
        if m:
            anchor = re.split(r"[,\s]+", m.group(1).strip())[0].strip("`'\"")
            refine = graph(anchor, "general", 600)
    total_g = g["tokens"] + (refine["tokens"] if refine else 0)
    hit_after = g_hit or (bool(refine["files"] & gt) if refine else False)
    # raw protocol: grep each keyword (case-insensitive, file list), rank files by distinct keyword hits, Read top 3
    score = {}
    grep_tokens = 0
    grep_secs = 0.0
    for kw in kws:
        r = rg("-il", kw, "lib")
        grep_tokens += r["tokens"]; grep_secs += r["secs"]
        for f in r["out"].split():
            score[f] = score.get(f, 0) + 1
    ranked = sorted(score, key=lambda f: (-score[f], f))
    top3 = ranked[:3]
    read_tokens = sum(read_cost(f) for f in top3)
    results.append(dict(kind="natural_language", q=q, gt=sorted(gt),
        graph=dict(tokens=total_g, secs=g["secs"] + (refine["secs"] if refine else 0), hit=hit_after,
                   first_hit=g_hit, refined=bool(refine), confidence=g["confidence"], files_listed=len(g["files"])),
        raw_typical=dict(tokens=grep_tokens + read_tokens, grep_tokens=grep_tokens, read_tokens=read_tokens,
                         secs=round(grep_secs, 2), hit=bool(set(top3) & gt), top3=top3, candidates=len(ranked))))

# ---------- 5. affected: current diff -> tests ----------
changed, _ = sh(["git", "diff", "--name-only", "HEAD", "--", "lib/"])
changed = [c for c in changed.split() if c.endswith(".dart")]
gt = set()
for c in changed:
    gt |= gt_tests(c)
g = graph(changed, None, 600, op="affected")
found = g["files"] & gt
raw_tok = 0; raw_secs = 0.0; raw_files = set()
for c in changed:
    r = rg("-l", Path(c).name, "test", "integration_test")
    raw_tok += r["tokens"]; raw_secs += r["secs"]; raw_files |= r["files"]
results.append(dict(kind="affected", q=changed, gt_n=len(gt),
    graph=dict(tokens=g["tokens"], secs=g["secs"], recall=round(len(found) / max(1, len(gt)), 2), found=len(found),
               listed=len(g["files"]), truncated=g["truncated"], out=g["out"]),
    raw_min=dict(tokens=raw_tok, secs=round(raw_secs, 2), recall=round(len(raw_files & gt) / max(1, len(gt)), 2))))

OUT.write_text(json.dumps(results, indent=1, default=sorted))
print(f"wrote {OUT} ({len(results)} cases)")
