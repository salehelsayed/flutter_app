#!/usr/bin/env python3
"""Contract suite for the project-memory deterministic recall layer.

Plan 381 rows (TC-381-01..11) + plan 382's session-memory ingestion pass
(TC-382-01..09).

Tier: tooling host (Python 3.9 + stdlib sqlite3). Outside every Flutter gate by
design -- TC-381-11 asserts that placement invariant from the gate side.

Fixtures are split deliberately:
  * SYNTHETIC mini-corpora (tempfile dirs) carry every PARSER RULE, so the rules
    are immune to plan-corpus drift.
  * REAL-corpus pins prove each rule is production-reachable in the live
    Test-Flight-Improv corpus. If a pin ever churns, re-census and fix the pin --
    never weaken the parser.

The plan-382 memory rows add a third axis: the live session-memory directory
lives OUTSIDE the repository, so every real-memory pin is `skipUnless`-guarded
and the synthetic fixtures carry the parser contract on machines (and CI
containers, and Codex) that have no memory directory at all.
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SRC_DIR = REPO_ROOT / "project-memory" / "src"
EVAL_DIR = REPO_ROOT / "project-memory" / "eval"
REAL_CORPUS = REPO_ROOT / "Test-Flight-Improv"

# The live session-memory directory. Deliberately a literal here: the test must
# pin the boundary independently of the builder's own constant (TC-382-01
# asserts the two agree), and importing a not-yet-existing constant would red
# the 13 plan-381 rows instead of only the plan-382 ones.
MEMORY_DIR = Path("/claude-home/.claude/projects/-workspace/memory")
HAS_MEMORY = MEMORY_DIR.is_dir()
needs_memory = unittest.skipUnless(
    HAS_MEMORY, "session-memory directory absent on this machine ({})".format(MEMORY_DIR)
)

sys.path.insert(0, str(SRC_DIR))

import build_graph  # noqa: E402
import recall as recall_mod  # noqa: E402
import run_eval  # noqa: E402


# --------------------------------------------------------------------------
# Synthetic corpus helpers
# --------------------------------------------------------------------------

def write_plan(directory, name, text):
    path = Path(directory) / name
    path.write_text(text, encoding="utf-8")
    return path


def build_into(corpus_dir, floor=1):
    db_path = Path(corpus_dir) / "graph.db"
    report = build_graph.build(Path(corpus_dir), db_path, floor=floor)
    return db_path, report


def statuses(db_path):
    rows = build_graph.query(
        db_path, "SELECT source_doc, status, status_raw FROM entities WHERE etype='PLAN'"
    )
    return {doc: (status, raw) for doc, status, raw in rows}


# --------------------------------------------------------------------------
# Real-corpus build, built once and shared (expensive relative to the asserts)
# --------------------------------------------------------------------------

_REAL = {}


def real_db():
    if "path" not in _REAL:
        tmp = tempfile.mkdtemp(prefix="project-memory-real-")
        _REAL["tmp"] = tmp
        db_path = Path(tmp) / "graph.db"
        _REAL["report"] = build_graph.build(REAL_CORPUS, db_path, floor=250)
        _REAL["path"] = db_path
    return _REAL["path"]


def real_report():
    real_db()
    return _REAL["report"]


def plan_status(db_path, number):
    rows = build_graph.query(
        db_path,
        "SELECT status FROM entities WHERE etype='PLAN' AND source_doc LIKE ?",
        ("%/{}-%".format(number),),
    )
    return sorted({row[0] for row in rows})


def names_for(db_path, etype, doc_fragment):
    rows = build_graph.query(
        db_path,
        "SELECT name FROM entities WHERE etype=? AND source_doc LIKE ?",
        (etype, "%{}%".format(doc_fragment)),
    )
    return [row[0] for row in rows]


# --------------------------------------------------------------------------
# Session-memory fixtures (plan 382)
# --------------------------------------------------------------------------

MEMORY_TEMPLATE = """---
name: {name}
description: {description}
metadata:
  node_type: memory
  type: {mtype}
  originSessionId: 00000000-0000-0000-0000-000000000000
{modified}---

{body}
"""


def write_memory(directory, name, description, body="Synthetic body.",
                 mtype="project", modified="2026-08-17T09:00:00.000Z"):
    """One synthetic memory file in the censused frontmatter shape."""
    path = Path(directory) / "{}.md".format(name)
    path.write_text(
        MEMORY_TEMPLATE.format(
            name=name,
            description=description,
            mtype=mtype,
            modified="  modified: {}\n".format(modified) if modified else "",
            body=body,
        ),
        encoding="utf-8",
    )
    return path


def memory_rows(db_path, etype="MEMORY"):
    """{name-slug: full entity row} for every MEMORY (or NOTE) entity."""
    rows = build_graph.query(
        db_path,
        "SELECT id, name, etype, status, status_raw, source_doc, source_line,"
        " source_commit, updated_date FROM entities WHERE etype=?",
        (etype,),
    )
    return {row[0].split(":", 1)[1]: row for row in rows}


def plan_facts(db_path):
    """Every plan-pass fact, in a form a memory pass must never be able to move."""
    entities = build_graph.query(
        db_path,
        "SELECT id, name, etype, status, status_raw, source_doc, source_line,"
        " source_commit, updated_date FROM entities"
        " WHERE etype IN ('PLAN','FINDING','GAP') ORDER BY id",
    )
    relations = build_graph.query(
        db_path,
        "SELECT src_id, dst_id, rtype, source_doc, source_line FROM relations"
        " WHERE rtype IN ('supersedes','refutes','deferred_to')"
        " ORDER BY src_id, dst_id, rtype, source_line",
    )
    return entities, relations


_REAL_MEMORY = {}


def real_db_with_memory():
    """Real plan corpus + the live memory directory, built once and shared."""
    if "path" not in _REAL_MEMORY:
        tmp = tempfile.mkdtemp(prefix="project-memory-real-mem-")
        _REAL_MEMORY["tmp"] = tmp
        db_path = Path(tmp) / "graph.db"
        _REAL_MEMORY["report"] = build_graph.build(
            REAL_CORPUS, db_path, floor=250, memory_dir=MEMORY_DIR
        )
        _REAL_MEMORY["path"] = db_path
    return _REAL_MEMORY["path"]


def real_memory_report():
    real_db_with_memory()
    return _REAL_MEMORY["report"]


# --------------------------------------------------------------------------


class TestBuild(unittest.TestCase):
    def test_build_deterministic_and_provenance_total(self):
        """TC-381-01: byte-identical rebuilds + total provenance."""
        with tempfile.TemporaryDirectory() as tmp:
            write_plan(tmp, "901-alpha-tdd-plan.md", ALPHA_PLAN)
            write_plan(tmp, "902-beta-tdd-plan.md", BETA_PLAN)
            db_path, _ = build_into(tmp)
            first = build_graph.content_hash(db_path)
            build_graph.build(Path(tmp), db_path, floor=1)
            second = build_graph.content_hash(db_path)
            self.assertEqual(first, second, "rebuild is not byte-stable")

            nulls = build_graph.query(
                db_path,
                "SELECT count(*) FROM entities WHERE status IS NULL OR status='' "
                "OR source_doc IS NULL OR source_doc='' OR source_line IS NULL "
                "OR source_commit IS NULL OR source_commit='' "
                "OR built_at IS NULL OR built_at=''",
            )
            self.assertEqual(nulls[0][0], 0, "entity rows are missing required provenance")
            total = build_graph.query(db_path, "SELECT count(*) FROM entities")[0][0]
            self.assertGreater(total, 0)

        # Sorted iteration is what makes the FILE bytes (not just the row set)
        # reproducible across machines, where directory order differs. The real
        # corpus is the fixture that can prove it: its filesystem glob order is
        # not alphabetical, so rowid order equals sorted order only if the
        # builder sorted deliberately.
        for table, columns in (
            ("entities", "id"),
            ("relations", "src_id, dst_id, rtype, source_doc, source_line"),
            ("aliases", "alias, entity_id"),
        ):
            physical = build_graph.query(
                real_db(), "SELECT {} FROM {} ORDER BY rowid".format(columns, table))
            self.assertEqual(
                physical, sorted(physical),
                "{} was not written in sorted order -- rebuilds are machine-dependent"
                .format(table),
            )

    def test_status_normalization_rule_table(self):
        """TC-381-02: normalization is a total function over the censused shapes."""
        shapes = {
            "910-a-tdd-plan.md": ("Status: execution-ready", "execution-ready"),
            "911-a-tdd-plan.md": ("Status: awaiting-review", "proposed"),
            "912-a-tdd-plan.md": ("Status: reviewed (adversarial pass)", "proposed"),
            "913-a-tdd-plan.md": ("Status: IMPLEMENTED host-green (2026-06-25)", "executed"),
            # Deliberately a bare `Plan-green` header: if the fixture carried a
            # second executed-tier keyword, deleting the Plan-green rule would
            # not re-red this case (TC-381-02's named mutation).
            "914-a-tdd-plan.md": ("Status: Plan-green", "executed"),
            "915-a-tdd-plan.md": ("Status: completed", "executed"),
            "916-a-tdd-plan.md": ("Status: accepted", "executed"),
            "917-a-tdd-plan.md": ("Status: **EXECUTED 2026-07-01**", "executed"),
            "918-a-tdd-plan.md": ("Status: CLOSED — device-proven 2026-06-29", "closed"),
            "919-a-tdd-plan.md": ("Status: DEVICE-GREEN — 175 freeze fix proven", "closed"),
            "920-a-tdd-plan.md": ("Status: evidence-gated", "unnormalized"),
            "921-a-tdd-plan.md": (None, "unknown"),
        }
        with tempfile.TemporaryDirectory() as tmp:
            for name, (header, _) in shapes.items():
                body = "# synthetic\n\n"
                if header:
                    body = "# synthetic\n\n{}\n\n".format(header)
                write_plan(tmp, name, body + "Prose only.\n")
            db_path, _ = build_into(tmp)
            got = statuses(db_path)
            for name, (header, expected) in shapes.items():
                key = [doc for doc in got if doc.endswith(name)]
                self.assertEqual(len(key), 1, "missing entity for {}".format(name))
                self.assertEqual(
                    got[key[0]][0], expected,
                    "{}: header {!r} normalized to {!r}, expected {!r}".format(
                        name, header, got[key[0]][0], expected),
                )
            # Raw text is preserved for the unnormalized bucket.
            junk = [doc for doc in got if doc.endswith("920-a-tdd-plan.md")][0]
            self.assertIn("evidence-gated", got[junk][1])

    def test_closure_evidence_outranks_header(self):
        """TC-381-03: in-file closure evidence beats a stale-open Status header."""
        with tempfile.TemporaryDirectory() as tmp:
            write_plan(tmp, "999-stale-header-tdd-plan.md", STALE_HEADER_PLAN)
            db_path, _ = build_into(tmp)
            got = statuses(db_path)
            doc = [key for key in got if key.endswith("999-stale-header-tdd-plan.md")][0]
            self.assertEqual(got[doc][0], "closed")
            self.assertIn("execution-ready", got[doc][1])  # both raws preserved

        # REAL pin: plan 377's line-3 header still reads execution-ready.
        header_line = ""
        for line in (REAL_CORPUS / "377-fresh-group-strict-authority-send-lockout-tdd-plan.md").read_text(
            encoding="utf-8"
        ).splitlines():
            if line.startswith("Status:"):
                header_line = line
                break
        self.assertIn("execution-ready", header_line, "pin drifted: 377 header changed")
        db = real_db()
        self.assertEqual(plan_status(db, 377), ["closed"])

        # Same inversion through a terminal-verdict SECTION rather than a
        # `PLAN NN CLOSED` line: 317's header still reads execution-ready while
        # its `## Execution Result` opens with "**CLOSED 2026-08-01.**".
        self.assertEqual(plan_status(db, 317), ["closed"])
        # ...and the two ways that scan must NOT over-read:
        #   259's verdict section is the placeholder "(pending)";
        #   135's verdict says "all 6 bugs CLOSED host-side" -- bugs, not the plan.
        self.assertEqual(plan_status(db, 259), ["execution-ready"])
        self.assertEqual(plan_status(db, 135), ["executed"])

    def test_refuted_findings_extraction(self):
        """TC-381-04: all three censused refuted-section shapes."""
        with tempfile.TemporaryDirectory() as tmp:
            write_plan(tmp, "930-shapes-tdd-plan.md", REFUTED_SHAPES_PLAN)
            db_path, _ = build_into(tmp)
            found = names_for(db_path, "FINDING", "930-shapes")
            blob = " || ".join(found)
            self.assertIn("shape-one bullet claim", blob)
            self.assertIn("shape-two inline claim", blob)
            self.assertIn("shape-three heading-table claim", blob)
            self.assertIn("shape-four bold-bullet claim", blob)
            for name in found:
                rows = build_graph.query(
                    db_path,
                    "SELECT status FROM entities WHERE etype='FINDING' AND name=?",
                    (name,),
                )
                self.assertEqual(rows[0][0], "refuted")
            edges = build_graph.query(
                db_path,
                "SELECT count(*) FROM relations WHERE rtype='refutes' AND source_doc LIKE ?",
                ("%930-shapes%",),
            )
            self.assertEqual(edges[0][0], len(found))
            self.assertGreaterEqual(len(found), 4)
            # Alias tokens make findings directly seedable.
            aliases = build_graph.query(
                db_path,
                "SELECT alias FROM aliases WHERE entity_id LIKE 'finding:%'",
            )
            self.assertIn("heading-table", " ".join(row[0] for row in aliases))

        db = real_db()
        pins = {"377-fresh": "genesis", "317-state": "skia", "315-group": "H1"}
        for fragment, needle in pins.items():
            blob = " || ".join(names_for(db, "FINDING", fragment))
            self.assertIn(needle, blob, "real pin {} lost {!r}".format(fragment, needle))

    def test_deferred_owner_extraction(self):
        """TC-381-05: deferred items keep their owner text."""
        with tempfile.TemporaryDirectory() as tmp:
            write_plan(tmp, "940-deferred-tdd-plan.md", DEFERRED_PLAN)
            db_path, _ = build_into(tmp)
            gaps = names_for(db_path, "GAP", "940-deferred")
            blob = " || ".join(gaps)
            self.assertIn("synthetic deferred item", blob)
            self.assertIn("owner: synthetic wave", blob)
            self.assertIn("Deferred device work: paired-phone replay", blob)
            # "none" placeholders must never become facts.
            self.assertNotIn("none", blob.lower())
            edges = build_graph.query(
                db_path,
                "SELECT count(*) FROM relations WHERE rtype='deferred_to' AND source_doc LIKE ?",
                ("%940-deferred%",),
            )
            self.assertEqual(edges[0][0], len(gaps))
            for gap in gaps:
                rows = build_graph.query(
                    db_path, "SELECT status FROM entities WHERE etype='GAP' AND name=?", (gap,)
                )
                self.assertEqual(rows[0][0], "deferred")

        gaps = names_for(real_db(), "GAP", "377-fresh")
        self.assertGreaterEqual(len(gaps), 4, "real pin: 377 deferred rows")
        blob = " || ".join(gaps)
        self.assertIn("multi-device wave", blob)
        self.assertIn("future plan", blob)

    def test_supersession_edge(self):
        """TC-381-06: supersession edge + superseded status on the older plan."""
        with tempfile.TemporaryDirectory() as tmp:
            write_plan(tmp, "950-old-tdd-plan.md", SUPERSEDED_PLAN)
            write_plan(tmp, "951-new-tdd-plan.md", "# 951\n\nStatus: accepted\n")
            db_path, _ = build_into(tmp)
            got = statuses(db_path)
            old = [key for key in got if key.endswith("950-old-tdd-plan.md")][0]
            self.assertEqual(got[old][0], "superseded")
            edges = build_graph.query(
                db_path,
                "SELECT src_id, dst_id FROM relations WHERE rtype='supersedes'",
            )
            self.assertEqual(len(edges), 1)
            self.assertTrue(edges[0][0].endswith("951-new-tdd-plan"))
            self.assertTrue(edges[0][1].endswith("950-old-tdd-plan"))
            # A prose mention that is not a closure heading must NOT create an edge.
            self.assertNotIn("952", " ".join(row[1] for row in edges))

        db = real_db()
        self.assertEqual(plan_status(db, 148), ["superseded"])
        edges = build_graph.query(
            db,
            "SELECT src_id, dst_id FROM relations WHERE rtype='supersedes' AND dst_id LIKE '%148-%'",
        )
        self.assertEqual(len(edges), 1)
        self.assertIn("327-", edges[0][0])
        # Self-referential prose in plan 381 must not supersede plan 381.
        self.assertNotIn("superseded", plan_status(db, 381))

    def test_corpus_floor_and_skip_report(self):
        """TC-381-07: census floor + no silent truncation."""
        report = real_report()
        self.assertGreaterEqual(report.parsed, 250, "real corpus fell below the census floor")
        rendered = report.render()
        self.assertIn("parsed", rendered)
        self.assertIn("skipped", rendered)
        self.assertIn("unnormalized", rendered)
        self.assertEqual(build_graph.CORPUS_GLOB, "*-tdd-plan.md")

        with tempfile.TemporaryDirectory() as tmp:
            for index in range(3):
                write_plan(tmp, "96{}-tiny-tdd-plan.md".format(index), "# tiny\n\nStatus: accepted\n")
            db_path = Path(tmp) / "graph.db"
            ok = build_graph.build(Path(tmp), db_path, floor=3)
            self.assertTrue(ok.floor_satisfied)
            low = build_graph.build(Path(tmp), db_path, floor=4)
            self.assertFalse(low.floor_satisfied)
            status = subprocess.call(
                [sys.executable, str(SRC_DIR / "build_graph.py"),
                 "--corpus", tmp, "--db", str(db_path), "--floor", "4"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            self.assertNotEqual(status, 0, "floor violation must exit nonzero")


class TestRecall(unittest.TestCase):
    def test_recall_deterministic_budgeted_grounded(self):
        """TC-381-08: deterministic, budget-bounded, fabrication-free."""
        db = real_db()
        first = recall_mod.recall(db, "plan 377 status", budget=700)
        second = recall_mod.recall(db, "plan 377 status", budget=700)
        self.assertEqual(first, second, "recall is not deterministic")

        self.assertLessEqual(recall_mod.token_count(first), 700)
        wide = recall_mod.recall(db, "group media notification plan status", budget=100000)
        self.assertLessEqual(recall_mod.token_count(wide), 1000, "hard cap not enforced")

        known_docs = {
            row[0] for row in build_graph.query(db, "SELECT DISTINCT source_doc FROM entities")
        }
        for line in first.splitlines():
            if "(" not in line:
                continue
            cited = line.rsplit("(", 1)[1].split(":")[0]
            self.assertTrue(
                any(doc.endswith(cited) or cited in doc for doc in known_docs),
                "recall cited a source not present in graph.db: {}".format(cited),
            )

        empty = recall_mod.recall(db, "zzzqqq nonexistent phrase", budget=700)
        self.assertEqual(empty, "No facts found for: zzzqqq nonexistent phrase")

    def test_recall_renders_relationships(self):
        """TC-381-09: relationship + provenance on the same fact line."""
        out = recall_mod.recall(real_db(), "plan 377", budget=900)
        lines = out.splitlines()
        self.assertTrue(
            any("[PLAN/closed]" in line for line in lines),
            "status not rendered on a fact line:\n{}".format(out),
        )
        refutes = [line for line in lines if "--refutes-->" in line and "genesis" in line]
        self.assertTrue(refutes, "refutes edge to the genesis finding not rendered:\n{}".format(out))
        self.assertRegex(refutes[0], r"\(\S+:\d+ @\S+\)$")
        deferred = [
            line for line in lines
            if "--deferred_to-->" in line and "owner:" in line
        ]
        self.assertTrue(deferred, "deferred_to line missing its owner:\n{}".format(out))
        self.assertRegex(deferred[0], r"\(\S+:\d+ @\S+\)$")


class TestEval(unittest.TestCase):
    def test_eval_gate_and_scorer_not_vacuous(self):
        """TC-381-10: gate over the 12 v1-scope questions + scorer vacuity guard."""
        expectations = run_eval.load_expectations(EVAL_DIR / "expected_facts.json")
        self.assertEqual(len(expectations), 30)
        scoped = [row for row in expectations if row["v1_scope"]]
        self.assertEqual(
            sorted(row["id"] for row in scoped),
            sorted(["Q1", "Q2", "Q3", "Q4", "Q5", "Q6", "Q9", "Q11", "Q12", "Q26", "Q27", "Q28"]),
        )

        db = real_db()
        results = run_eval.score(db, scoped)
        misses = [row for row in results if not row["pass"]]
        self.assertEqual(misses, [], "v1-scope gate misses: {}".format(
            [(row["id"], row["missing"]) for row in misses]))
        for row in results:
            self.assertLessEqual(row["tokens"], 1000)

        report = run_eval.score(db, expectations)
        self.assertEqual(len(report), 30)
        for row in report:
            self.assertIn("tokens", row)

        # Scorer vacuity: a doctored expectation must fail, and it must fail
        # because the OUTPUT lacks the substring -- not because the query does.
        doctored = json.loads(json.dumps(scoped))
        doctored[0]["required"] = ["zzz-nonexistent-literal"]
        doctored_results = run_eval.score(db, doctored)
        self.assertFalse(doctored_results[0]["pass"], "scorer is vacuous")

        # A term that IS in the query but can never be in the output. A scorer
        # that matched the query instead of the output would pass this row --
        # which is exactly the mutation TC-381-10 names.
        echo = json.loads(json.dumps(scoped))
        echo[0]["query"] = echo[0]["query"] + " zzzunfindableterm"
        echo[0]["required"] = ["zzzunfindableterm"]
        echoed = run_eval.score(db, echo)
        self.assertNotIn("zzzunfindableterm", echoed[0]["output"])
        self.assertFalse(
            echoed[0]["pass"],
            "scorer credited a term that appears only in the question, not the answer",
        )


# --------------------------------------------------------------------------
# Synthetic fixture bodies (shapes copied from the 2026-08-17 corpus census)
# --------------------------------------------------------------------------

ALPHA_PLAN = """# 901 - Alpha

Status: execution-ready

## Problem And Evidence
- Refuted findings:
  - "alpha claim" — REFUTED by census.
- Deferred device work: alpha rig replay.
"""

BETA_PLAN = """# 902 - Beta

Status: IMPLEMENTED host-green (2026-07-04)

## Scope
- Beta item deferred → owner: beta wave, because it needs a schema change.
"""

STALE_HEADER_PLAN = """# 999 - Stale header

Status: execution-ready

## Execution Progress
| Time | Phase | Evidence |
|---|---|---|
| 2026-08-17 | device | **PLAN 999 CLOSED at device tier** |
"""

REFUTED_SHAPES_PLAN = """# 930 - Refuted shapes

Status: accepted

## Problem And Evidence
- Refuted findings:
  - "shape-one bullet claim" — refuted by source.
  - "shape-one second claim" — also refuted.
- Refuted findings (do NOT re-introduce): "shape-two inline claim" is refuted on mechanism.
- **Refuted findings (do NOT re-introduce):** "shape-four bold-bullet claim" is refuted.
- Unresolved findings: none material.

### Refuted findings (do NOT re-introduce)

| Finding | Why refuted |
|---|---|
| **shape-three heading-table claim** | No such predicate exists at any layer. |

### Unresolved findings
- Nothing here should become a refuted finding.
"""

DEFERRED_PLAN = """# 940 - Deferred

Status: accepted

## Scope Contract And Guard
Deferred / accepted difference:
- A synthetic deferred item that stays open → owner: synthetic wave, because it needs a rig.
- Deferred device work: paired-phone replay.
- Deferred device work: none.
- Another item → owner: none.
"""

SUPERSEDED_PLAN = """# 950 - Old plan

Status: BLOCKED on Phase-0 evidence gate

## Planning Progress
That pending wording is superseded by plan 952's accepted intentional non-goal.

## CLOSED — superseded by plan 951 (user decision, 2026-08-02)
The scope moved wholesale.
"""


class TestRecallStatusline(unittest.TestCase):
    """Statusline fragment: day-scoped adoption counter over recall_stats.jsonl."""

    def _run(self, ledger, today):
        import recall_statusline
        return recall_statusline.fragment(Path(ledger), today)

    def test_counts_today_only_and_hits(self):
        with tempfile.TemporaryDirectory() as tmp:
            ledger = Path(tmp) / "recall_stats.jsonl"
            rows = [
                {"ts": "2026-08-17T10:00:00+00:00", "hit": True},
                {"ts": "2026-08-17T11:00:00+00:00", "hit": False},
                {"ts": "2026-08-17T12:00:00+00:00", "hit": True},
                {"ts": "2026-08-16T09:00:00+00:00", "hit": True},  # other day
                "not json at all",
            ]
            ledger.write_text(
                "\n".join(r if isinstance(r, str) else json.dumps(r) for r in rows)
                + "\n", encoding="utf-8")
            self.assertEqual(self._run(ledger, "2026-08-17"), "recall 3 (2 hit)")

    def test_ledger_exists_but_quiet_today_shows_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            ledger = Path(tmp) / "recall_stats.jsonl"
            ledger.write_text(
                json.dumps({"ts": "2026-08-16T09:00:00+00:00", "hit": True}) + "\n",
                encoding="utf-8")
            self.assertEqual(self._run(ledger, "2026-08-17"), "recall 0",
                             "deployed-but-unused must stay visible")

    def test_no_ledger_prints_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(self._run(Path(tmp) / "missing.jsonl", "2026-08-17"), "")


# --------------------------------------------------------------------------
# Plan 382 -- session-memory ingestion (TC-382-01..09)
# --------------------------------------------------------------------------

SYNTHETIC_PLAN_999 = """# 999 - Synthetic closed plan

Status: CLOSED — device-proven 2026-08-17

## Execution Result
**CLOSED 2026-08-17.** Device tier proven.
"""

SYNTHETIC_PLAN_998 = """# 998 - Synthetic open plan

Status: execution-ready

## Problem And Evidence
- Refuted findings: "synthetic refuted claim" — refuted by census.
"""

# The 12 plan-381 gate rows, frozen. TC-382-07's "do not weaken a v1 term" guard
# compares eval/expected_facts.json against this literal, so a silent edit to a
# v1 row reds the suite rather than quietly shrinking the 381 contract.
V1_REQUIRED = {
    "Q1": ["377", "closed"],
    "Q2": ["263", "267", "executed"],
    "Q3": ["302", "executed"],
    "Q4": ["303", "executed"],
    "Q5": ["259", "execution-ready"],
    "Q6": ["317", "state-guard"],
    "Q9": ["genesis", "refuted"],
    "Q11": ["nomination", "refuted"],
    "Q12": ["skia", "refuted"],
    "Q26": ["linked-device UX"],
    "Q27": ["multi-device wave", "notMember"],
    "Q28": ["future plan", "376"],
}

# The loose single keywords those 6 rows carried while they were ungated.
# RECALL-RESULTS.md records why they are not answers: `custody` / `deploy` /
# `host-all` prove "related facts surfaced", not "the question was answered".
V2_LOOSE_BEFORE = {
    "Q8": ["test/unit"],
    "Q15": ["custody"],
    "Q19": ["custody"],
    "Q21": ["deploy"],
    "Q25": ["host-all"],
    "Q30": ["worktree"],
}

PLAN_381_ROWS = {
    "TestBuild": [
        "test_build_deterministic_and_provenance_total",
        "test_status_normalization_rule_table",
        "test_closure_evidence_outranks_header",
        "test_refuted_findings_extraction",
        "test_deferred_owner_extraction",
        "test_supersession_edge",
        "test_corpus_floor_and_skip_report",
    ],
    "TestRecall": [
        "test_recall_deterministic_budgeted_grounded",
        "test_recall_renders_relationships",
    ],
    "TestEval": ["test_eval_gate_and_scorer_not_vacuous"],
    "TestRecallStatusline": [
        "test_counts_today_only_and_hits",
        "test_ledger_exists_but_quiet_today_shows_zero",
        "test_no_ledger_prints_nothing",
    ],
}


class TestMemoryPass(unittest.TestCase):
    """The second corpus pass: session memory -> MEMORY entities + edges."""

    @needs_memory
    def test_memory_pass_parses_real_dir(self):
        """TC-382-01: the live memory directory parses, with total provenance."""
        self.assertEqual(
            Path(build_graph.DEFAULT_MEMORY_DIR), MEMORY_DIR,
            "builder default drifted from the boundary this suite pins",
        )
        db = real_db_with_memory()
        report = real_memory_report()
        rows = memory_rows(db)

        self.assertGreaterEqual(
            len(rows), 60, "memory census floor: expected >=60 fact files")
        self.assertEqual(report.memory_parsed, len(rows))

        # The generated index has no frontmatter and is not a fact.
        self.assertNotIn("MEMORY", rows)
        skipped = dict(report.memory_skipped)
        self.assertIn("MEMORY.md", skipped, "MEMORY.md must be skipped, and reported")
        for row in rows.values():
            self.assertNotIn(
                "MEMORY.md", row[5], "the generated index leaked in as a fact")

        notes = memory_rows(db, etype="NOTE")
        self.assertEqual(sorted(notes), sorted(rows),
                         "every memory fact must carry its description node")
        for source in (rows, notes):
            for slug, row in sorted(source.items()):
                _id, name, _etype, status, _raw, doc, line, commit, updated = row
                self.assertTrue(status, "{}: empty status".format(slug))
                self.assertTrue(doc.startswith("/"),
                                "{}: source_doc not absolute".format(slug))
                self.assertTrue(doc.endswith("{}.md".format(slug)),
                                "{}: doc/name drift".format(slug))
                self.assertEqual(line, 1)
                self.assertTrue(commit, "{}: empty source_commit".format(slug))
                self.assertTrue(name, "{}: empty name".format(slug))
                self.assertIsNotNone(updated, "{}: null updated_date".format(slug))
                self.assertRegex(updated, r"^\d{4}-\d{2}-\d{2}$")
        # The MEMORY node is named by the frontmatter `name`, verbatim.
        for slug, row in sorted(rows.items()):
            self.assertEqual(row[1], slug, "MEMORY node is not its frontmatter name")

        rendered = report.render()
        self.assertIn("memory: {} parsed".format(report.memory_parsed), rendered)
        self.assertIn("memory skipped:", rendered)
        self.assertIn("memory unresolved links:", rendered)

    def test_memory_staleness_markers(self):
        """TC-382-02: SUPERSEDED / CORRECTED / active, and prose must not trigger."""
        with tempfile.TemporaryDirectory() as corpus, \
                tempfile.TemporaryDirectory() as memory:
            write_plan(corpus, "997-tiny-tdd-plan.md", "# 997\n\nStatus: accepted\n")
            write_memory(memory, "synthetic-superseded-note",
                         "SUPERSEDED 2026-08-09: the earlier claim no longer holds")
            write_memory(memory, "synthetic-corrected-note",
                         "a claim that was revised",
                         body="**Corrected 2026-08-09.** The earlier reading was wrong.")
            write_memory(memory, "synthetic-status-corrected-note",
                         "another revised claim",
                         body="**How to apply — STATUS CORRECTED 2026-08-17.**")
            write_memory(memory, "synthetic-active-note",
                         "a live fact whose prose merely discusses supersession",
                         body="Plan 148 was superseded by plan 327; that is history, "
                              "not a marker on this memory.",
                         mtype="feedback")
            # A marker inside backticks documents the vocabulary; it must not
            # stale the memory that documents it.
            write_memory(memory, "synthetic-documents-the-markers",
                         "explains the marker rule without being stale itself",
                         body="Statuses come from `SUPERSEDED` and `CORRECTED`:\n\n"
                              "```\nSUPERSEDED -> superseded\nCORRECTED -> corrected\n```\n")
            # Identity comes from the frontmatter `name`, not the filename. Every
            # live memory file happens to agree with its own name, so only a
            # deliberately mismatched fixture can hold that rule.
            renamed = write_memory(memory, "synthetic-renamed-note", "a renamed fact")
            renamed.rename(Path(memory) / "zz-not-the-frontmatter-name.md")

            db_path = Path(corpus) / "graph.db"
            build_graph.build(Path(corpus), db_path, floor=1, memory_dir=Path(memory))
            rows = memory_rows(db_path)

            self.assertIn("synthetic-renamed-note", rows,
                          "entity identity fell back to the filename")
            self.assertNotIn("zz-not-the-frontmatter-name", rows)
            self.assertTrue(rows["synthetic-renamed-note"][5].endswith(
                "zz-not-the-frontmatter-name.md"), "source_doc must stay the real file")

            self.assertEqual(rows["synthetic-superseded-note"][3], "superseded")
            self.assertEqual(rows["synthetic-corrected-note"][3], "corrected")
            self.assertEqual(rows["synthetic-status-corrected-note"][3], "corrected")
            self.assertEqual(
                rows["synthetic-active-note"][3], "active",
                "lowercase prose about supersession must not stale a live memory",
            )
            self.assertEqual(
                rows["synthetic-documents-the-markers"][3], "active",
                "a backticked marker is documentation of the vocabulary, not a marker",
            )
            # status_raw keeps the frontmatter type AND the marker that decided.
            self.assertIn("project", rows["synthetic-superseded-note"][4])
            self.assertIn("SUPERSEDED", rows["synthetic-superseded-note"][4])
            self.assertIn("feedback", rows["synthetic-active-note"][4])

        if not HAS_MEMORY:
            self.skipTest("real-memory pins need the session-memory directory")
        rows = memory_rows(real_db_with_memory())
        for slug in ("test-unit-invisible-to-per-plan-gates",
                     "host-all-not-runnable-from-container"):
            self.assertEqual(rows[slug][3], "superseded",
                             "real pin drifted: {}".format(slug))
        for slug in ("group-exit-reliability-plans",
                     "plan-303-view-once-minimal-presentation"):
            self.assertEqual(rows[slug][3], "corrected",
                             "real pin drifted: {}".format(slug))
        for slug in ("project-memory-recall-layer", "relay-ec2-deployment"):
            self.assertEqual(
                rows[slug][3], "active",
                "{} discusses supersession in prose; it is not itself stale".format(slug),
            )

    def test_memory_never_overrides_plan_facts(self):
        """TC-382-03: the memory pass writes MEMORY rows and edges. Nothing else.

        This is the 5-stale-memories incident in miniature: on 2026-08-17 five
        memory entries were proven stale against the plan corpus. Memory is the
        layer that goes stale, so artifacts win -- always.
        """
        with tempfile.TemporaryDirectory() as corpus, \
                tempfile.TemporaryDirectory() as memory:
            write_plan(corpus, "999-synthetic-tdd-plan.md", SYNTHETIC_PLAN_999)
            write_plan(corpus, "998-synthetic-tdd-plan.md", SYNTHETIC_PLAN_998)
            plain = Path(corpus) / "plain.db"
            build_graph.build(Path(corpus), plain, floor=1)
            before = plan_facts(plain)
            self.assertTrue(before[0], "fixture produced no plan facts")

            write_memory(
                memory, "poisoned-claim-about-plan-999",
                "plan 999 is execution-ready and NOT executed; plan 998 is closed",
                body="This memory deliberately contradicts both plan headers. "
                     "It must never move a plan fact.",
            )
            poisoned = Path(corpus) / "poisoned.db"
            build_graph.build(Path(corpus), poisoned, floor=1, memory_dir=Path(memory))
            after = plan_facts(poisoned)

            self.assertEqual(
                before, after,
                "the memory pass moved a plan-pass fact -- precedence guard broken",
            )
            statuses_after = {
                row[0]: row[3] for row in after[0] if row[0].startswith("plan:")
            }
            self.assertEqual(statuses_after["plan:999-synthetic-tdd-plan"], "closed")
            self.assertEqual(
                statuses_after["plan:998-synthetic-tdd-plan"], "execution-ready")

            # A plan mention becomes an edge -- and only an edge.
            edges = build_graph.query(
                poisoned,
                "SELECT src_id, dst_id, rtype FROM relations"
                " WHERE src_id LIKE 'memory:%' ORDER BY dst_id",
            )
            self.assertIn(
                ("memory:poisoned-claim-about-plan-999",
                 "plan:999-synthetic-tdd-plan", "references"), edges)
            self.assertIn(
                ("memory:poisoned-claim-about-plan-999",
                 "plan:998-synthetic-tdd-plan", "references"), edges)
            for _src, dst, rtype in edges:
                if dst.startswith("note:"):
                    self.assertEqual(rtype, "asserts")
                    continue
                self.assertEqual(
                    rtype, "references",
                    "a memory may only `reference` anything outside its own note",
                )
            # No plan-pass entity may ever be sourced from the memory directory.
            leaked = build_graph.query(
                poisoned,
                "SELECT count(*) FROM entities"
                " WHERE etype NOT IN ('MEMORY','NOTE') AND source_doc LIKE ?",
                ("{}%".format(memory),),
            )
            self.assertEqual(leaked[0][0], 0)
            # ...and no memory-pass entity may claim a plan doc as its source.
            reverse = build_graph.query(
                poisoned,
                "SELECT count(*) FROM entities"
                " WHERE etype IN ('MEMORY','NOTE') AND source_doc NOT LIKE ?",
                ("{}%".format(memory),),
            )
            self.assertEqual(reverse[0][0], 0)

    def test_memory_wiki_links_become_edges(self):
        """TC-382-04: [[links]] -> references edges; unresolved are reported, never invented."""
        with tempfile.TemporaryDirectory() as corpus, \
                tempfile.TemporaryDirectory() as memory:
            write_plan(corpus, "997-tiny-tdd-plan.md", "# 997\n\nStatus: accepted\n")
            write_memory(memory, "synthetic-link-source",
                         "a memory that points at a sibling and at a ghost",
                         body="See [[synthetic-link-target]] and "
                              "[[synthetic-ghost-target]].")
            write_memory(memory, "synthetic-link-target", "the sibling that exists")
            db_path = Path(corpus) / "graph.db"
            report = build_graph.build(
                Path(corpus), db_path, floor=1, memory_dir=Path(memory))

            edges = build_graph.query(
                db_path,
                "SELECT src_id, dst_id, rtype FROM relations WHERE src_id LIKE 'memory:%'",
            )
            self.assertIn(
                ("memory:synthetic-link-source", "memory:synthetic-link-target",
                 "references"), edges)
            ghosts = build_graph.query(
                db_path, "SELECT count(*) FROM entities WHERE id LIKE '%ghost%'")
            self.assertEqual(ghosts[0][0], 0, "an unresolved link was fabricated into a node")
            self.assertIn(
                ("synthetic-link-source", "synthetic-ghost-target"),
                report.memory_unresolved_links,
                "unresolved links must be counted and printed",
            )
            self.assertIn("synthetic-ghost-target", report.render())

        if not HAS_MEMORY:
            self.skipTest("real-memory pins need the session-memory directory")
        db = real_db_with_memory()
        pairs = build_graph.query(
            db,
            "SELECT DISTINCT src_id, dst_id FROM relations"
            " WHERE rtype='references' AND src_id LIKE 'memory:%' AND dst_id LIKE 'memory:%'",
        )
        self.assertGreaterEqual(
            len(pairs), 35,
            "real pin: the live memory corpus cross-links far more than this",
        )

    def test_memory_dir_absent_is_tolerated(self):
        """TC-382-05: no memory directory -> exit 0 and a byte-identical plan-only graph."""
        with tempfile.TemporaryDirectory() as corpus:
            write_plan(corpus, "999-synthetic-tdd-plan.md", SYNTHETIC_PLAN_999)
            write_plan(corpus, "998-synthetic-tdd-plan.md", SYNTHETIC_PLAN_998)
            plain = Path(corpus) / "plain.db"
            build_graph.build(Path(corpus), plain, floor=1)
            plain_hash = build_graph.content_hash(plain)

            missing = Path(corpus) / "no-such-memory-directory"
            absent = Path(corpus) / "absent.db"
            report = build_graph.build(
                Path(corpus), absent, floor=1, memory_dir=missing)
            self.assertTrue(report.memory_absent)
            self.assertEqual(report.memory_parsed, 0)
            self.assertIn("memory source absent (0 files)", report.render())
            self.assertEqual(
                build_graph.content_hash(absent), plain_hash,
                "an absent memory directory changed the plan-only graph",
            )

            process = subprocess.run(
                [sys.executable, str(SRC_DIR / "build_graph.py"),
                 "--corpus", corpus, "--db", str(absent),
                 "--floor", "1", "--memory-dir", str(missing)],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            self.assertEqual(process.returncode, 0, process.stderr.decode())
            self.assertIn("memory source absent (0 files)",
                          process.stdout.decode("utf-8", "replace"))

            # ...and the gate follows the builder: with no memory SOURCE the six
            # v2 rows are untestable, not failing. v1 stays gated regardless.
            original = build_graph.DEFAULT_MEMORY_DIR
            try:
                build_graph.DEFAULT_MEMORY_DIR = missing
                self.assertFalse(run_eval.memory_source_present())
                self.assertFalse(run_eval.gated({"v1_scope": False, "v2_scope": True}))
                self.assertTrue(run_eval.gated({"v1_scope": True, "v2_scope": False}))
            finally:
                build_graph.DEFAULT_MEMORY_DIR = original
            self.assertTrue(run_eval.gated({"v1_scope": False, "v2_scope": True})
                            is (True if HAS_MEMORY else False))

    def test_memory_pass_deterministic_with_date_fallback(self):
        """TC-382-06: rebuilds are byte-stable; a missing `modified:` falls back to mtime."""
        with tempfile.TemporaryDirectory() as corpus, \
                tempfile.TemporaryDirectory() as memory:
            write_plan(corpus, "999-synthetic-tdd-plan.md", SYNTHETIC_PLAN_999)
            write_memory(memory, "synthetic-dated-note", "carries a modified stamp",
                         modified="2026-07-19T20:03:41.758Z")
            undated = write_memory(memory, "synthetic-undated-note",
                                   "carries no modified stamp at all", modified=None)
            # Created in reverse-alphabetical order, each dangling a ghost link:
            # the census lists below can only come out sorted if the pass sorted
            # its glob, and file-creation order is what an unsorted glob follows.
            for extra in reversed(range(6)):
                write_memory(memory, "synthetic-bulk-{}".format(extra),
                             "bulk memory {} for sort stability".format(extra),
                             body="Dangling: [[ghost-{}]].".format(extra))

            db_path = Path(corpus) / "graph.db"
            report = build_graph.build(
                Path(corpus), db_path, floor=1, memory_dir=Path(memory))
            first = build_graph.content_hash(db_path)
            build_graph.build(Path(corpus), db_path, floor=1, memory_dir=Path(memory))
            self.assertEqual(first, build_graph.content_hash(db_path),
                             "memory pass is not byte-stable across rebuilds")

            # Row CONTENT is order-proof either way -- `_write` sorts every row
            # unconditionally. What the sorted glob buys is a reproducible
            # CENSUS: the skip/unresolved report is the no-silent-truncation
            # record, and it must read the same on every machine.
            self.assertEqual(len(report.memory_unresolved_links), 6)
            self.assertEqual(
                report.memory_unresolved_links,
                sorted(report.memory_unresolved_links),
                "the memory census is filesystem-order dependent",
            )

            for table, columns in (
                ("entities", "id"),
                ("relations", "src_id, dst_id, rtype, source_doc, source_line"),
                ("aliases", "alias, entity_id"),
            ):
                physical = build_graph.query(
                    db_path, "SELECT {} FROM {} ORDER BY rowid".format(columns, table))
                self.assertEqual(physical, sorted(physical),
                                 "{} left sorted order once memory rows joined".format(table))

            rows = memory_rows(db_path)
            self.assertEqual(rows["synthetic-dated-note"][8], "2026-07-19")
            expected = build_graph.mtime_date(undated)
            self.assertEqual(rows["synthetic-undated-note"][8], expected)
            self.assertRegex(rows["synthetic-undated-note"][8], r"^\d{4}-\d{2}-\d{2}$")

    def test_plan_381_suite_rows_intact(self):
        """TC-382-08: the plan-381 contract rows still exist, under their own names."""
        module = sys.modules[__name__]
        for class_name, methods in PLAN_381_ROWS.items():
            case = getattr(module, class_name, None)
            self.assertIsNotNone(case, "plan-381 class {} was removed".format(class_name))
            for method in methods:
                self.assertTrue(
                    callable(getattr(case, method, None)),
                    "plan-381 row {}::{} was removed or renamed".format(class_name, method),
                )
        self.assertEqual(
            sum(len(methods) for methods in PLAN_381_ROWS.values()), 13)


class TestMemoryEvalAndRecall(unittest.TestCase):
    """The eval flip and recall integration for MEMORY facts."""

    @needs_memory
    def test_eval_gate_covers_v2_scope(self):
        """TC-382-07: 18/18 gated, v1 terms byte-unchanged, v2 terms non-vacuous."""
        expectations = run_eval.load_expectations(EVAL_DIR / "expected_facts.json")
        self.assertEqual(len(expectations), 30)
        by_id = {row["id"]: row for row in expectations}

        # v1 rows are frozen: not one required term may be weakened to buy a v2 hit.
        v1 = [row for row in expectations if row.get("v1_scope")]
        self.assertEqual(sorted(row["id"] for row in v1), sorted(V1_REQUIRED))
        for row in v1:
            self.assertEqual(row["required"], V1_REQUIRED[row["id"]],
                             "v1 row {} was edited".format(row["id"]))
            self.assertFalse(row.get("v2_scope"), "a v1 row must not also claim v2 scope")

        v2 = [row for row in expectations if row.get("v2_scope")]
        self.assertEqual(sorted(row["id"] for row in v2), sorted(V2_LOOSE_BEFORE))
        for row in v2:
            self.assertGreaterEqual(
                len(row["required"]), 2,
                "{}: a single loose keyword is not an answer".format(row["id"]))
            self.assertNotEqual(
                row["required"], V2_LOOSE_BEFORE[row["id"]],
                "{}: required terms were reverted to the loose keyword".format(row["id"]))

        gated = [row for row in expectations if run_eval.gated(row)]
        self.assertEqual(len(gated), 18)

        db = real_db_with_memory()
        results = run_eval.score(db, gated)
        misses = [(row["id"], row["missing"]) for row in results if not row["pass"]]
        self.assertEqual(misses, [], "gated misses: {}".format(misses))
        for row in results:
            self.assertLessEqual(row["tokens"], 1000)

        # Causal proof that the v2 rows are answered BY the memory pass: the same
        # rows must miss against a plan-only graph. This is TC-382-07's named
        # mutation ("revert the memory pass -> the 6 red") as an assertion.
        plan_only = run_eval.score(real_db(), [by_id[qid] for qid in sorted(V2_LOOSE_BEFORE)])
        still_passing = [row["id"] for row in plan_only if row["pass"]]
        self.assertEqual(
            still_passing, [],
            "v2 rows answerable without memory: {} -- the gate is vacuous".format(
                still_passing),
        )

    @needs_memory
    def test_recall_surfaces_memory_facts(self):
        """TC-382-09: a MEMORY fact recalls with status, path, date and its edge."""
        db = real_db_with_memory()
        out = recall_mod.recall(
            db, "why must workspace never be stashed and what is the alternative git worktree",
            budget=900)
        lines = out.splitlines()

        entity_lines = [
            line for line in lines
            if line.startswith("workspace-live-checkout-no-stash [") and "-->" not in line
        ]
        self.assertTrue(entity_lines, "memory fact not recalled:\n{}".format(out))
        fact = entity_lines[0]
        self.assertIn("[MEMORY/active]", fact)
        self.assertIn(str(MEMORY_DIR), fact, "absolute source path not rendered")
        # Provenance tail carries the build commit AND the memory's own date, so
        # a memory fact can never be read without its recency.
        self.assertRegex(fact, r"\(\S+\.md:1 @\S+\+mem:\d{4}-\d{2}-\d{2}\)$")

        edges = [
            line for line in lines
            if "--references-->" in line and "workspace-live-checkout-no-stash" in line
        ]
        self.assertTrue(edges, "no references edge rendered:\n{}".format(out))
        self.assertRegex(edges[0], r"\(\S+:\d+ @\S+\)$")

        # Underscore-preserving aliases: a screaming-snake flag name seeds directly.
        flag = recall_mod.recall(db, "DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED", budget=700)
        self.assertIn("custody-admission-flag-breaks-offline-delivery", flag)
        self.assertNotIn("No facts found", flag)


if __name__ == "__main__":
    unittest.main(verbosity=2)
