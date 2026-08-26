#!/usr/bin/env python3
"""Build the C4 level-2 page from the codebase.

Reads:
  C4/c4-manifest.json      the hand-written part (names, plain English, layout)
  the architecture graph   under graphify-arch/graphify-out/ (links between files)
  the repo itself          the file and test census

Writes:
  C4/c4.json                       the computed data, for inspection
  C4/c4-level2-inside-mknoon.html  the page, with the data inlined

Run from the repo root:  python3 C4/build_c4.py
"""
import json, os, sys, collections, datetime, html

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "C4", "c4-manifest.json")
GRAPH = os.path.join(ROOT, "graphify-arch", "graphify-out", "graph" + ".json")
OUT_JSON = os.path.join(ROOT, "C4", "c4.json")
OUT_HTML = os.path.join(ROOT, "C4", "c4-level2-inside-mknoon.html")

SCAN_DIRS = ["lib", "test", "integration_test", "go-mknoon", "go-relay-server", "ios", "android"]
SKIP_PARTS = {"build", "Pods", ".dart_tool", "node_modules", "third_party", ".git",
              "graphify-out", ".symlinks", "DerivedData", "vendor", "gen"}
CODE_EXT = {".dart", ".go", ".swift", ".kt", ".java", ".m", ".mm"}


def is_test(path):
    base = os.path.basename(path)
    return (path.startswith("test/") or path.startswith("integration_test/")
            or base.endswith("_test.go") or base.endswith("_test.dart")
            or base.endswith("Tests.swift") or base.endswith("Test.kt")
            or "/RunnerTests/" in path or "/src/test/" in path)


def census():
    """Every code file in the repo, from disk. Kotlin is missing from the graph,
    so file counts never come from the graph."""
    files = []
    for top in SCAN_DIRS:
        for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, top)):
            dirnames[:] = [d for d in dirnames if d not in SKIP_PARTS and not d.startswith(".")]
            for name in filenames:
                if os.path.splitext(name)[1] in CODE_EXT:
                    files.append(os.path.relpath(os.path.join(dirpath, name), ROOT))
    return sorted(files)


def matcher(globs):
    def hit(path):
        return any(path == g or path.startswith(g) for g in globs)
    return hit


def assign(files, comps, order):
    """First component in claim_order that matches wins the file."""
    by_id = {c["id"]: c for c in comps}
    src = {cid: matcher(by_id[cid].get("files", [])) for cid in order}
    tst = {cid: matcher(by_id[cid].get("tests", [])) for cid in order}
    owner = {}
    for path in files:
        for cid in order:
            if is_test(path):
                if tst[cid](path):
                    owner[path] = cid
                    break
            elif src[cid](path):
                owner[path] = cid
                break
    return owner


def comp_of_factory(comps, order):
    """Component for ANY path, existing or not (import targets are not files on disk)."""
    by_id = {c["id"]: c for c in comps}
    src = {cid: matcher(by_id[cid].get("files", [])) for cid in order}
    tst = {cid: matcher(by_id[cid].get("tests", [])) for cid in order}

    def comp_of(path):
        if not path:
            return None
        table = tst if is_test(path) else src
        for cid in order:
            if table[cid](path):
                return cid
        return None
    return comp_of


def resolve_import(label, from_file):
    """Turn an import target into a repo path. The graph stores the package name,
    not the file, so this is where a Dart or Go import becomes something we can place."""
    label = str(label or "")
    if label.startswith("package:flutter_app/"):
        return "lib/" + label[len("package:flutter_app/"):]
    if label.startswith("github.com/mknoon/go-mknoon/"):
        return "go-mknoon/" + label[len("github.com/mknoon/go-mknoon/"):]
    if label.startswith((".", "..")) and from_file:
        return os.path.normpath(os.path.join(os.path.dirname(from_file), label))
    return None


def main():
    man = json.load(open(MANIFEST))
    comps = man["components"]
    order = man["claim_order"]
    files = census()
    owner = assign(files, comps, order)

    comp_of = comp_of_factory(comps, order)
    graph_links = collections.Counter()      # production wires, by relation
    test_links = collections.Counter()       # a test on one side reaching the other
    symbols = collections.Counter()
    graph_commit = None
    if os.path.exists(GRAPH):
        g = json.load(open(GRAPH))
        graph_commit = g.get("built_at_commit")
        node = {n["id"]: n for n in g["nodes"]}
        node_file = {i: str(n.get("source_file") or "") for i, n in node.items()}
        for path in node_file.values():
            cid = owner.get(path)
            if cid:
                symbols[cid] += 1
        for link in g["links"]:
            rel = link.get("relation")
            fa = node_file.get(link["source"], "") or str(link.get("source_file") or "")
            if rel == "imports":
                # the target is a package name; turn it back into a path
                fb = resolve_import(node.get(link["target"], {}).get("label"), fa)
            else:
                fb = node_file.get(link["target"], "")
            if not fa or not fb or fa == fb:
                continue
            a, b = comp_of(fa), comp_of(fb)
            if not a or not b or a == b:
                continue
            bucket = test_links if is_test(fa) else graph_links
            bucket[(a, b, rel)] += 1
    else:
        print("WARNING: architecture graph not found at %s" % GRAPH, file=sys.stderr)

    def links_between(x, y, counter):
        out = collections.Counter()
        for (a, b, rel), n in counter.items():
            if {a, b} == {x, y}:
                out[rel] += n
        return out

    data_comps = []
    for c in comps:
        mine = [p for p, cid in owner.items() if cid == c["id"]]
        src = sorted(p for p in mine if not is_test(p))
        tst = sorted(p for p in mine if is_test(p))
        langs = collections.Counter(os.path.splitext(p)[1] for p in src)
        data_comps.append({**c,
                           "counts": {"files": len(src), "tests": len(tst),
                                      "symbols": symbols.get(c["id"], 0)},
                           "languages": ["%d %s" % (n, e[1:]) for e, n in langs.most_common(3)],
                           "test_examples": [os.path.basename(p) for p in tst[:4]],
                           "source_files": src[:400], "test_files": tst[:600]})

    data_conns = []
    for k in man["connections"]:
        sides = []
        for side in k.get("sides", []):
            hit = matcher(side["tests"])
            found = sorted(p for p in files if is_test(p) and hit(p))
            sides.append({"of": side["of"], "globs": side["tests"], "count": len(found),
                          "examples": [os.path.basename(p) for p in found[:4]]})
        prod = links_between(k["from"], k["to"], graph_links)
        fromtests = links_between(k["from"], k["to"], test_links)
        data_conns.append({**k, "sides": sides,
                           "graph_links": sum(prod.values()),
                           "graph_breakdown": dict(prod.most_common()),
                           "graph_links_from_tests": sum(fromtests.values()),
                           "tests_total": sum(s["count"] for s in sides)})

    fixtures = dict(man.get("shared_fixtures", {}))
    fixtures["present"] = [r for r in fixtures.get("readers", [])
                           if os.path.exists(os.path.join(ROOT, r))]

    out = {"title": man["title"], "subtitle": man["subtitle"],
           "boundary": man["boundary"], "canvas": man["canvas"],
           "components": data_comps, "connections": data_conns,
           "shared_fixtures": fixtures,
           "story": man.get("story", {}), "notes": man.get("notes", {}),
           "proper_names": man.get("proper_names", {}),
           "built": {"date": datetime.date.today().isoformat(),
                     "graph_commit": graph_commit,
                     "code_files_scanned": len(files),
                     "files_claimed": len(owner)}}
    json.dump(out, open(OUT_JSON, "w"), indent=2)
    open(OUT_HTML, "w").write(render(out))

    print("components:")
    for c in out["components"]:
        n = c["counts"]
        print("  %-13s files=%-5d tests=%-5d symbols=%d" % (c["id"], n["files"], n["tests"], n["symbols"]))
    print("connections:")
    for k in out["connections"]:
        per = " ".join("%s=%d" % (s["of"], s["count"]) for s in k["sides"])
        print("  %-18s kind=%-8s links=%-5d (%s) from_tests=%-5d tests[%s]"
              % (k["id"], k["kind"], k["graph_links"],
                 ", ".join("%s %d" % (r, n) for r, n in k["graph_breakdown"].items()) or "none",
                 k["graph_links_from_tests"], per))
    print("\nwrote %s\nwrote %s" % (OUT_JSON, OUT_HTML))


# --------------------------------------------------------------------------- render
FILL = {"person": "b-person", "app": "b-system", "sidecar": "b-supporting",
        "phone": "b-external", "external": "b-external"}
MARK = {"solid": "✓", "one_sided": "△", "device_only": "△"}


def esc(s):
    return html.escape(str(s), quote=True)


def wrap(text, width):
    words, lines, cur = str(text).split(), [], ""
    for w in words:
        if len(cur) + len(w) + 1 > width and cur:
            lines.append(cur)
            cur = w
        else:
            cur = (cur + " " + w).strip()
    if cur:
        lines.append(cur)
    return lines


def box_lines(c, layer):
    n = c["counts"]
    if layer == "components":
        return c["blurb"]
    if layer == "tests":
        if not n["tests"]:
            return ["No tests of its own — it is a", "person, or it sits outside", "this drawing."]
        return ["%d test files" % n["tests"]] + ["· " + e for e in c["test_examples"]]
    if not n["files"]:
        return ["Not code in this repo."]
    body = ["%d source files" % n["files"], "%d named things in the graph" % n["symbols"]]
    if c["languages"]:
        body.append("mostly " + ", ".join(c["languages"]))
    return body


def wire_lines(k, layer):
    if layer == "components":
        return k["plain"]
    if layer == "tests":
        head = "tested end to end" if k["verdict"] == "solid" else "each side on its own stand-in"
        out = [MARK.get(k["verdict"], "") + " " + head]
        for s in k["sides"]:
            out.append("%s: %d test files" % (s["of"], s["count"]))
        return out + wrap(k["note"], 42)
    out = [k["wire"]]
    if k["graph_links"]:
        out.append("%d links: %s" % (k["graph_links"],
                   ", ".join("%d %s" % (n, r) for r, n in k["graph_breakdown"].items())))
    else:
        out.append("0 links — the graph follows imports,")
        out.append("and this wire is not an import")
    if k["graph_links_from_tests"]:
        out.append("+ %d more from test files" % k["graph_links_from_tests"])
    return out


def name_of(d, cid):
    for c in d["components"]:
        if c["id"] == cid:
            return c["name"]
    return cid


def render(d):
    svg = ['<svg viewBox="0 0 %d %d" role="img" aria-label="%s">'
           % (d["canvas"]["w"], d["canvas"]["h"], esc(d["title"])),
           '<defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" '
           'markerHeight="7" orient="auto-start-reverse">'
           '<path d="M0,0 L10,5 L0,10 z" fill="var(--line)"/></marker></defs>']
    b = d["boundary"]
    svg.append('<rect class="boundary" x="%d" y="%d" width="%d" height="%d" rx="14"/>'
               % (b["x"], b["y"], b["w"], b["h"]))
    svg.append('<text class="boundary-label" x="%d" y="%d">%s</text>'
               % (b["x"] + 18, b["y"] + 24, esc(b["label"])))

    for c in d["components"]:
        L = c["layout"]
        cls = FILL[c["kind"]]
        cx = L["x"] + L["w"] / 2
        svg.append("<g>")
        if L.get("head"):
            h = L["head"]
            svg.append('<circle class="%s" cx="%d" cy="%d" r="%d"/>' % (cls, h["cx"], h["cy"], h["r"]))
        svg.append('<rect class="%s" x="%d" y="%d" width="%d" height="%d" rx="8"/>'
                   % (cls, L["x"], L["y"], L["w"], L["h"]))
        y = L["y"] + 38
        svg.append('<text class="t-title" x="%s" y="%d" text-anchor="middle">%s</text>'
                   % (cx, y, esc(c["name"])))
        if c["type"]:
            y += 18
            svg.append('<text class="t-type" x="%s" y="%d" text-anchor="middle">%s</text>'
                       % (cx, y, esc(c["type"])))
        top = y + 26
        for layer in ("components", "tests", "io"):
            svg.append('<g class="lyr lyr-%s">' % layer)
            for i, line in enumerate(box_lines(c, layer)):
                svg.append('<text class="t-desc" x="%s" y="%d" text-anchor="middle">%s</text>'
                           % (cx, top + i * 16, esc(line)))
            svg.append("</g>")
        svg.append("</g>")

    for k in d["connections"]:
        dash = " edge-dash" if k.get("dashed") else ""
        ends = ' marker-end="url(#arrow)"'
        if k["arrow"] == "both":
            ends += ' marker-start="url(#arrow)"'
        svg.append('<path class="edge%s" d="%s"%s/>' % (dash, k["path"], ends))
        lab = k["label"]
        for layer in ("components", "tests", "io"):
            svg.append('<g class="lyr lyr-%s">' % layer)
            for i, line in enumerate(wire_lines(k, layer)):
                svg.append('<text class="edge-label" x="%d" y="%d" text-anchor="%s">%s</text>'
                           % (lab["x"], lab["y"] + i * 15, lab["anchor"], esc(line)))
            svg.append("</g>")
    svg.append("</svg>")

    rows_c = "".join(
        "<tr><td>%s</td><td>%s</td><td>%d</td><td>%d</td><td>%d</td><td><code>%s</code></td></tr>"
        % (esc(c["name"]), esc(c.get("desc", "")), c["counts"]["files"], c["counts"]["symbols"],
           c["counts"]["tests"], esc(", ".join(c["files"]) or "—"))
        for c in d["components"] if c["kind"] != "person")
    rows_k = "".join(
        "<tr><td>%s &#8594; %s</td><td>%s</td><td>%s</td><td>%s</td><td>%s %s</td></tr>"
        % (esc(name_of(d, k["from"])), esc(name_of(d, k["to"])), esc(k["wire"]),
           esc(("%d (%s)" % (k["graph_links"], ", ".join("%d %s" % (n, r)
                for r, n in k["graph_breakdown"].items()))) if k["graph_links"] else "0"),
           "<br>".join("%s: %d files" % (esc(s["of"]), s["count"]) for s in k["sides"]) or "—",
           MARK.get(k["verdict"], ""), esc(k["note"]))
        for k in d["connections"])
    fx = d["shared_fixtures"]
    fx_rows = "".join("<li><code>%s</code></li>" % esc(r) for r in fx.get("present", []))
    built = d["built"]
    commit = (built["graph_commit"] or "unknown")[:9]
    story = d.get("story") or {}
    story_html = "".join("<li>%s</li>" % esc(x) for x in story.get("steps", []))
    notes = d.get("notes") or {}
    notes_html = "".join(
        "<li>%s%s</li>" % (("<strong>%s</strong> " % esc(h)) if h else "",
                           esc(t)) for h, t in notes.get("items", []))
    pn = d.get("proper_names") or {}
    pn_html = "".join("<tr><td>%s</td><td>%s</td></tr>" % (esc(a), b) for a, b in pn.get("rows", []))

    return """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Inside mknoon</title>
<style>
:root{--bg:#f6f7f9;--card:#fff;--fg:#16191d;--fg-muted:#5b636c;--border:#dfe3e8;--line:#7b848d;
--accent:#1168bd;--chip-bg:#eef2f6;--table-head:#f0f3f6;--table-row:#fafbfc;--person:#08427b;
--system:#1168bd;--supporting:#2e6295;--external:#6b6b6b;--on-fill:#fff;--on-fill-dim:#cfdcea}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#14171a;--card:#1c2023;
--fg:#e8eaed;--fg-muted:#a7b0b8;--border:#2e3438;--line:#98a2ab;--accent:#5aa9e6;--chip-bg:#252b30;
--table-head:#232930;--table-row:#1f2428;--person:#0d4f8f;--system:#1d78d0;--supporting:#3a76ab;
--external:#7d858c;--on-fill:#fff;--on-fill-dim:#d8e4f0}}
:root[data-theme="dark"]{--bg:#14171a;--card:#1c2023;--fg:#e8eaed;--fg-muted:#a7b0b8;--border:#2e3438;
--line:#98a2ab;--accent:#5aa9e6;--chip-bg:#252b30;--table-head:#232930;--table-row:#1f2428;
--person:#0d4f8f;--system:#1d78d0;--supporting:#3a76ab;--external:#7d858c;--on-fill:#fff;
--on-fill-dim:#d8e4f0}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font-size:15px;line-height:1.6;
font-family:ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}
.wrap{max-width:1180px;margin:0 auto;padding:40px 20px 72px}
h1{font-size:1.8rem;line-height:1.2;margin:0 0 8px;letter-spacing:-.01em}
.sub{color:var(--fg-muted);margin:0 0 14px;max-width:66ch}
.chips{display:flex;flex-wrap:wrap;gap:8px}
.chip{background:var(--chip-bg);border:1px solid var(--border);color:var(--fg-muted);
font-size:.75rem;padding:3px 9px;border-radius:999px;white-space:nowrap}
.card{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:18px;margin:22px 0}
.scroll{overflow-x:auto}svg{display:block;width:100%;min-width:940px;height:auto}
h2{font-size:1.1rem;margin:34px 0 10px}h2 .num{color:var(--accent);margin-right:8px}
.tabs{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:14px}
.tab{font:inherit;font-size:.85rem;padding:6px 14px;border-radius:999px;cursor:pointer;
border:1px solid var(--border);background:var(--chip-bg);color:var(--fg-muted)}
.tab[aria-pressed="true"]{background:var(--accent);border-color:var(--accent);color:#fff}
.legend{display:flex;flex-wrap:wrap;gap:18px;margin-top:16px;padding-top:16px;
border-top:1px solid var(--border);font-size:.82rem;color:var(--fg-muted)}
.legend span{display:flex;align-items:center;gap:7px}
.sw{width:14px;height:14px;border-radius:3px;display:inline-block}
table{width:100%;border-collapse:collapse;font-size:.86rem}
th,td{text-align:left;padding:9px 11px;border-bottom:1px solid var(--border);vertical-align:top}
th{background:var(--table-head);font-weight:600;font-size:.76rem;text-transform:uppercase;
letter-spacing:.04em;color:var(--fg-muted)}
tbody tr:nth-child(even){background:var(--table-row)}td:first-child{font-weight:600}
code{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:.85em;
background:var(--chip-bg);padding:1px 5px;border-radius:4px}
ul{margin:8px 0 0;padding-left:20px}li{margin:5px 0}.muted{color:var(--fg-muted)}
footer{margin-top:40px;padding-top:16px;border-top:1px solid var(--border);color:var(--fg-muted);
font-size:.8rem}
.b-person{fill:var(--person)}.b-system{fill:var(--system)}.b-supporting{fill:var(--supporting)}
.b-external{fill:var(--external)}
.t-title{fill:var(--on-fill);font-size:14px;font-weight:700}
.t-type{fill:var(--on-fill-dim);font-size:10.5px;font-style:italic}
.t-desc{fill:var(--on-fill);font-size:11px;opacity:.94}
.edge{stroke:var(--line);stroke-width:1.7;fill:none}.edge-dash{stroke-dasharray:6 4}
.edge-label{fill:var(--fg-muted);font-size:11px;paint-order:stroke;stroke:var(--bg);
stroke-width:4px;stroke-linejoin:round}
.boundary{fill:none;stroke:var(--line);stroke-width:1.3;stroke-dasharray:7 6;opacity:.55}
.boundary-label{fill:var(--fg-muted);font-size:11.5px;font-style:italic;opacity:.9}
#stage .lyr{display:none}
#stage[data-layer="components"] .lyr-components,
#stage[data-layer="tests"] .lyr-tests,
#stage[data-layer="io"] .lyr-io{display:inline}
</style></head><body><div class="wrap">
<header>
<h1>__TITLE__</h1>
<p class="sub">__SUB__</p>
<div class="chips">
<span class="chip">Built from the code on __DATE__</span>
<span class="chip">graph at commit __COMMIT__</span>
<span class="chip">__SCANNED__ code files scanned</span>
<span class="chip">generated by C4/build_c4.py</span>
</div></header>

<div class="card">
<div class="tabs" role="group" aria-label="Choose a layer">
<button class="tab" data-l="components" aria-pressed="true">Components</button>
<button class="tab" data-l="tests" aria-pressed="false">Tests</button>
<button class="tab" data-l="io" aria-pressed="false">Inputs and outputs</button>
</div>
<div class="scroll" id="stage" data-layer="components">
__SVG__
</div>
<div class="legend">
<span><i class="sw" style="background:var(--person)"></i>A person</span>
<span><i class="sw" style="background:var(--system)"></i>Part of the app</span>
<span><i class="sw" style="background:var(--supporting)"></i>Runs on its own</span>
<span><i class="sw" style="background:var(--external)"></i>The phone, or outside this drawing</span>
<span>&#10003; tested against the real thing</span>
<span>&#9651; both sides tested, but only against stand-ins</span>
</div></div>

<h2><span class="num">1</span>The parts, counted from the code</h2>
<div class="card scroll"><table>
<thead><tr><th>Part</th><th>What it does</th><th>Source files</th><th>Named things</th>
<th>Test files</th><th>Where it lives</th></tr></thead>
<tbody>__ROWSC__</tbody></table></div>

<h2><span class="num">2</span>The connections, counted from the graph</h2>
<div class="card scroll"><table>
<thead><tr><th>Connection</th><th>What kind of wire</th><th>Links in the graph</th>
<th>Tests each side</th><th>How solid</th></tr></thead>
<tbody>__ROWSK__</tbody></table></div>
<p class="muted" style="font-size:.86rem">A zero in the third column is not a missing test. It means the
graph cannot follow that wire at all. It follows imports, and a channel between two languages is not an
import. Those wires are named by hand in <code>C4/c4-manifest.json</code> and are checked on a real phone.</p>

<h2><span class="num">3</span>The one shared contract</h2>
<div class="card">
<p style="margin:0 0 8px">__FXNOTE__ The files live in <code>__FXDIR__</code>.</p>
<ul>__FXROWS__</ul>
</div>

<h2><span class="num">4</span>__STORYTITLE__</h2>
<div class="card"><ol>__STORY__</ol></div>

<h2><span class="num">5</span>__NOTESTITLE__</h2>
<div class="card"><ul>__NOTES__</ul></div>

<h2><span class="num">6</span>__PNTITLE__</h2>
<div class="card"><p class="muted" style="margin:0 0 8px">Same parts, in the words an engineer would
use.</p><table><thead><tr><th>Plain name</th><th>Technical name</th></tr></thead>
<tbody>__PN__</tbody></table></div>

<h2><span class="num">7</span>How to rebuild this page</h2>
<div class="card">
<ul>
<li><code>python3 C4/build_c4.py</code> — re-counts everything and rewrites this page.</li>
<li><code>C4/c4-manifest.json</code> — the only hand-written part: the names, the plain English, the
layout, and the wires the graph cannot see.</li>
<li><code>C4/c4.json</code> — the computed data, if you want to feed it somewhere else.</li>
<li>Run <code>./graphify-arch/refresh_arch_graph.sh --incremental</code> first if the code moved, so the
link counts are current.</li>
</ul>
</div>

<footer>Generated from the codebase &#183; __DATE__ &#183; __CLAIMED__ of __SCANNED__ scanned files
belong to a part above</footer>
</div>
<script>
var stage = document.getElementById('stage');
document.querySelectorAll('.tab').forEach(function (t) {
  t.addEventListener('click', function () {
    document.querySelectorAll('.tab').forEach(function (o) { o.setAttribute('aria-pressed', 'false'); });
    t.setAttribute('aria-pressed', 'true');
    stage.setAttribute('data-layer', t.dataset.l);
  });
});
</script>
</body></html>""".replace("__TITLE__", esc(d["title"])) \
    .replace("__SUB__", esc(d["subtitle"])) \
    .replace("__DATE__", esc(built["date"])) \
    .replace("__COMMIT__", esc(commit)) \
    .replace("__SCANNED__", str(built["code_files_scanned"])) \
    .replace("__CLAIMED__", str(built["files_claimed"])) \
    .replace("__SVG__", "".join(svg)) \
    .replace("__ROWSC__", rows_c) \
    .replace("__ROWSK__", rows_k) \
    .replace("__FXNOTE__", esc(fx.get("note", ""))) \
    .replace("__FXDIR__", esc(fx.get("dir", ""))) \
    .replace("__FXROWS__", fx_rows) \
    .replace("__STORYTITLE__", esc(story.get("title", "Walkthrough"))) \
    .replace("__STORY__", story_html) \
    .replace("__NOTESTITLE__", esc(notes.get("title", "Notes"))) \
    .replace("__NOTES__", notes_html) \
    .replace("__PNTITLE__", esc(pn.get("title", "The proper names"))) \
    .replace("__PN__", pn_html)


if __name__ == "__main__":
    main()
