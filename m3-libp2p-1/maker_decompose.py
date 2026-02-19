#!/usr/bin/env python3
"""
maker_decompose.py

Takes:
  - a Feature spec (text/markdown)
  - a C4 model description (text/markdown)

Outputs:
  - a set of small, single-deliverable "tiny story" task files in the style of FL_XS_01 / JS_XS_01 / DB_XS_01 / QA_XS_01
  - an index file that lists ordering + dependencies

Design goals:
  - Small connected steps
  - One deliverable file per task (works with maker_2.sh)
  - TDD-oriented plan with:
      - unit-level tasks where appropriate
      - at least 1 smoke test task
      - at least 1 integration test task
  - No mock data: tests should run against real components (local DB, real backend, etc.) using ephemeral/dev config
  - MVP scope: avoid overengineering

Dependencies:
  - "claude" CLI available on PATH (used for decomposition + task writing)
  - Optional: "codex" CLI (used as judge). If missing, script uses claude as judge.

Usage:
  python3 maker_decompose.py \
    --feature feature.md \
    --c4 c4.md \
    --out tasks/mvp_feature_x \
    --milestone MVP1 \
    --prefix XS \
    --k 3 \
    --candidates 5 \
    --judge-calls 9

Then run maker_2.sh per task file in dependency order.

"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


# -----------------------------
# CLI helpers
# -----------------------------

def have_cmd(name: str) -> bool:
    from shutil import which
    return which(name) is not None


def run_cmd(cmd: List[str], stdin_text: Optional[str] = None, timeout_s: int = 600) -> Tuple[int, str, str]:
    p = subprocess.run(
        cmd,
        input=stdin_text,
        text=True,
        capture_output=True,
        timeout=timeout_s,
    )
    return p.returncode, (p.stdout or ""), (p.stderr or "")


def run_claude(prompt: str, timeout_s: int = 900) -> str:
    if not have_cmd("claude"):
        raise RuntimeError("Missing required CLI: claude")
    rc, out, err = run_cmd(["claude", "-p", "-", "--dangerously-skip-permissions"], stdin_text=prompt, timeout_s=timeout_s)
    # claude may return non-zero in some environments; treat output as authoritative if any
    text = (out or "").strip()
    if not text:
        raise RuntimeError(f"claude returned empty output (rc={rc}). stderr:\n{err}")
    return text


def run_codex(prompt: str, timeout_s: int = 900) -> str:
    if not have_cmd("codex"):
        raise RuntimeError("Missing required CLI: codex")
    # codex CLI takes prompt as an argument; keep prompt short in judge mode.
    rc, out, err = run_cmd(
        ["codex", "exec", prompt, "--dangerously-bypass-approvals-and-sandbox", "--skip-git-repo-check", "--model", "gpt-5.2-codex"],
        stdin_text=None,
        timeout_s=timeout_s,
    )
    text = (out or "").strip()
    if not text:
        raise RuntimeError(f"codex returned empty output (rc={rc}). stderr:\n{err}")
    return text


# -----------------------------
# Parsing / validation
# -----------------------------

def extract_first_json_object(text: str) -> str:
    """
    Extract the first {...} JSON object from a string.
    This tolerates models that accidentally wrap JSON with prose.
    """
    start = text.find("{")
    if start == -1:
        raise ValueError("No '{' found")
    depth = 0
    for i in range(start, len(text)):
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[start:i+1]
    raise ValueError("Unbalanced JSON braces")


def must_json(text: str) -> Dict[str, Any]:
    blob = extract_first_json_object(text)
    return json.loads(blob)


def sanitize_filename(s: str) -> str:
    s = s.strip()
    s = re.sub(r"[^a-zA-Z0-9_.-]+", "_", s)
    s = re.sub(r"_+", "_", s)
    return s.strip("_")


def find_next_index(out_dir: Path, prefix: str, story_prefix: str) -> int:
    """
    For files like FL_XS_01.md, returns next index per component prefix.
    """
    pat = re.compile(rf"^{re.escape(prefix)}_{re.escape(story_prefix)}_(\d{{2}})\.md$")
    max_n = 0
    if out_dir.exists():
        for p in out_dir.iterdir():
            if not p.is_file():
                continue
            m = pat.match(p.name)
            if m:
                max_n = max(max_n, int(m.group(1)))
    return max_n + 1


# -----------------------------
# Data model
# -----------------------------

@dataclass
class TaskBlueprint:
    key: str                 # stable dependency key
    component: str           # FL / JS / DB / QA
    title: str
    owner: str
    deliverable: str         # single output file path
    depends_on: List[str]    # list of blueprint keys
    intent: str              # short goal / why
    must_include: List[str]  # bullet requirements
    verification: List[str]  # commands / checks
    test_type: str           # "unit" | "integration" | "smoke" | "feature" | ...


# -----------------------------
# Prompts
# -----------------------------

PLAN_SCHEMA = """\
Return STRICT JSON (no markdown) with this schema:

{
  "milestone": "<string>",
  "global_context": "<string, short and reusable across tasks>",
  "tasks": [
    {
      "key": "<unique stable key, like 'db_identity_migration'>",
      "component": "FL" | "JS" | "DB" | "QA",
      "title": "<short title>",
      "owner": "<Flutter|JS|DB|QA>",
      "deliverable": "<single repo file path to be produced by maker_2.sh>",
      "depends_on": ["<key>", "..."],
      "test_type": "unit" | "integration" | "smoke" | "feature",
      "intent": "<why this task exists>",
      "must_include": ["<requirement 1>", "<requirement 2>", "..."],
      "verification": ["<command/check 1>", "<command/check 2>", "..."]
    }
  ]
}

Hard constraints:
- Output only JSON.
- Each task MUST have exactly ONE deliverable file path.
- Use only these components: FL, JS, DB, QA.
- Plan MUST include:
  - at least one QA smoke test task (real end-to-end, no mocks)
  - at least one QA integration test task (real DB + real backend + real contracts)
- MVP scope: smallest set of tasks that yields a working feature end-to-end.
- No mock data: tests must run against real components (local/dev config is fine).
- TDD oriented: include test tasks early in dependencies (even if they won't pass until code exists).
- Tasks must be connected through explicit dependencies and shared contracts (API payloads, DB schema, routes).
"""

JUDGE_INSTRUCTIONS = """\
You are judging decomposition plans for an MVP feature implementation.

Pick the plan that best satisfies:
- Connected steps with explicit dependencies
- Small single-deliverable tasks
- Covers FL + JS + DB as needed (and QA tests)
- TDD oriented (tests appear early; smoke + integration tests exist)
- No mock data in tests
- MVP scope (not overcomplicated)

Answer with ONLY the candidate number (e.g., 1). Nothing else.
"""

TASK_MD_TEMPLATE_HINT = """\
Your output must be a SINGLE markdown task file in this style:

- Title line: "Task Prompt: <ID> - <Title>"
- Sections:
  - "## Instructions for AI Agent"
  - "## Global Context" (code block)
  - "## Task Definition" (code block, includes Owner, Goal, What to implement, Constraints, Deliverable)
  - "## Output Requirements" (must include File: <deliverable>)
  - "## Verification Steps" (commands/checks)

Hard constraints:
- Exactly ONE deliverable file path (the one provided).
- Keep scope minimal and implementable.
- Include explicit acceptance criteria and contracts.
- Tests: if QA task, it must use real flows (no mocks).
"""


def build_plan_prompt(feature_text: str, c4_text: str, milestone: str) -> str:
    return f"""You are a software decomposition agent.

Inputs:
- Milestone: {milestone}

FEATURE (what we want to implement):
{feature_text}

C4 MODEL (architecture / components / boundaries / integration points):
{c4_text}

Produce a decomposition plan for an MVP implementation.

{PLAN_SCHEMA}
"""


def build_judge_prompt(candidates: List[Dict[str, Any]]) -> str:
    # Keep judge prompt short: include only titles + task counts + a compact summary of deliverables
    lines = [JUDGE_INSTRUCTIONS, ""]
    for i, c in enumerate(candidates, start=1):
        tasks = c.get("tasks", [])
        deliverables = []
        for t in tasks[:12]:
            deliverables.append(f'{t.get("component","?")}:{t.get("deliverable","?")}')
        more = "" if len(tasks) <= 12 else f" (+{len(tasks)-12} more)"
        lines.append(f"Candidate {i}: milestone={c.get('milestone','')}, tasks={len(tasks)}")
        lines.append(f"  deliverables: {', '.join(deliverables)}{more}")
        lines.append("")
    return "\n".join(lines).strip()


def build_task_markdown_prompt(
    *,
    task_id: str,
    blueprint: TaskBlueprint,
    global_context: str,
    milestone: str,
    feature_text: str,
    c4_text: str,
    dependency_ids: List[str],
) -> str:
    deps = ", ".join(dependency_ids) if dependency_ids else "None"
    must = "\n".join([f"- {x}" for x in blueprint.must_include]) if blueprint.must_include else "- None"
    verif = "\n".join([f"- {x}" for x in blueprint.verification]) if blueprint.verification else "- None"

    return f"""Write ONE markdown tiny-story task file.

Milestone: {milestone}
Task ID: {task_id}
Component: {blueprint.component}
Owner: {blueprint.owner}
Title: {blueprint.title}
Deliverable (single file): {blueprint.deliverable}
Dependencies: {deps}
Test type: {blueprint.test_type}

Feature:
{feature_text}

C4 model:
{c4_text}

Global context (reuse this in the task's Global Context section; keep it concise):
{global_context}

Task intent:
{blueprint.intent}

Must include requirements:
{must}

Verification steps:
{verif}

{TASK_MD_TEMPLATE_HINT}

CRITICAL:
- Output ONLY the markdown file content. No surrounding commentary.
- The Deliverable and "File:" MUST exactly be: {blueprint.deliverable}
"""


# -----------------------------
# Core logic
# -----------------------------

def pick_best_plan(
    candidates: List[Dict[str, Any]],
    k: int,
    judge_calls: int,
    judge_backend: str,
) -> Dict[str, Any]:
    votes = {i: 0 for i in range(len(candidates))}
    prompt = build_judge_prompt(candidates)

    def judge_once() -> int:
        if judge_backend == "codex" and have_cmd("codex"):
            out = run_codex(prompt)
        else:
            out = run_claude(prompt)
        out = out.strip()
        m = re.search(r"\b([1-9][0-9]?)\b", out)
        if not m:
            return -1
        n = int(m.group(1))
        if 1 <= n <= len(candidates):
            return n - 1
        return -1

    # first-to-ahead-by-k, but bounded by judge_calls for practicality
    for _ in range(judge_calls):
        idx = judge_once()
        if idx >= 0:
            votes[idx] += 1

        # find top2
        ranked = sorted(votes.items(), key=lambda kv: kv[1], reverse=True)
        top_i, top_v = ranked[0]
        second_v = ranked[1][1] if len(ranked) > 1 else 0
        if top_v >= second_v + k:
            return candidates[top_i]

    # fallback: argmax
    best_i = max(votes.items(), key=lambda kv: kv[1])[0]
    return candidates[best_i]


def to_blueprints(plan: Dict[str, Any]) -> Tuple[str, List[TaskBlueprint], str]:
    milestone = str(plan.get("milestone", "")).strip() or "MVP"
    global_context = str(plan.get("global_context", "")).strip()
    raw_tasks = plan.get("tasks", [])
    if not isinstance(raw_tasks, list) or not raw_tasks:
        raise ValueError("Plan has no tasks")

    bps: List[TaskBlueprint] = []
    for t in raw_tasks:
        bps.append(
            TaskBlueprint(
                key=str(t["key"]),
                component=str(t["component"]),
                title=str(t["title"]),
                owner=str(t.get("owner", t["component"])),
                deliverable=str(t["deliverable"]),
                depends_on=list(t.get("depends_on", [])) if isinstance(t.get("depends_on", []), list) else [],
                intent=str(t.get("intent", "")),
                must_include=list(t.get("must_include", [])) if isinstance(t.get("must_include", []), list) else [],
                verification=list(t.get("verification", [])) if isinstance(t.get("verification", []), list) else [],
                test_type=str(t.get("test_type", "feature")),
            )
        )
    return milestone, bps, global_context


def render_tasks(
    *,
    out_dir: Path,
    story_prefix: str,
    milestone: str,
    feature_text: str,
    c4_text: str,
    global_context: str,
    blueprints: List[TaskBlueprint],
    max_task_attempts: int,
) -> List[Path]:
    out_dir.mkdir(parents=True, exist_ok=True)

    # assign IDs per component
    next_idx = {
        "FL": find_next_index(out_dir, "FL", story_prefix),
        "JS": find_next_index(out_dir, "JS", story_prefix),
        "DB": find_next_index(out_dir, "DB", story_prefix),
        "QA": find_next_index(out_dir, "QA", story_prefix),
    }

    key_to_id: Dict[str, str] = {}
    key_to_path: Dict[str, Path] = {}

    # stable assignment in listed order
    for bp in blueprints:
        comp = bp.component.strip().upper()
        if comp not in next_idx:
            raise ValueError(f"Unknown component '{comp}' (allowed: FL, JS, DB, QA)")
        task_id = f"{comp}_{story_prefix}_{next_idx[comp]:02d}"
        next_idx[comp] += 1
        key_to_id[bp.key] = task_id
        key_to_path[bp.key] = out_dir / f"{task_id}.md"

    written: List[Path] = []

    # generate markdown per task with red-flagging
    for bp in blueprints:
        task_id = key_to_id[bp.key]
        path = key_to_path[bp.key]
        deps_ids = [key_to_id[k] for k in bp.depends_on if k in key_to_id]

        prompt = build_task_markdown_prompt(
            task_id=task_id,
            blueprint=bp,
            global_context=global_context,
            milestone=milestone,
            feature_text=feature_text,
            c4_text=c4_text,
            dependency_ids=deps_ids,
        )

        ok = False
        last_err = ""
        for attempt in range(1, max_task_attempts + 1):
            md = run_claude(prompt)

            # red-flag: must mention deliverable file
            if bp.deliverable not in md:
                last_err = f"Deliverable path missing/mismatched (attempt {attempt})"
                continue

            # must look like a task file
            if "## Task Definition" not in md or "## Output Requirements" not in md:
                last_err = f"Missing required sections (attempt {attempt})"
                continue

            # must have the title line format
            if not md.lstrip().startswith("Task Prompt:"):
                last_err = f"Missing 'Task Prompt:' header (attempt {attempt})"
                continue

            path.write_text(md, encoding="utf-8")
            written.append(path)
            ok = True
            break

        if not ok:
            raise RuntimeError(f"Failed to generate task markdown for {task_id}: {last_err}")

    # write index
    index_path = out_dir / "00_INDEX.md"
    lines: List[str] = []
    lines.append(f"# {milestone} — Decomposition Index\n")
    lines.append("## Task Order\n")
    for bp in blueprints:
        tid = key_to_id[bp.key]
        deps = [key_to_id[k] for k in bp.depends_on if k in key_to_id]
        deps_s = ", ".join(deps) if deps else "None"
        lines.append(f"- **{tid}** — {bp.title}  \n  - Component: {bp.component} | Deliverable: `{bp.deliverable}`  \n  - Depends on: {deps_s}\n")

    lines.append("\n## Run Order Guidance\n")
    lines.append("1) Implement tasks in dependency order (topologically).  \n2) Run unit checks per component (flutter analyze / tsc / migrations).  \n3) Run integration test task(s).  \n4) Run smoke test task(s) last.\n")
    index_path.write_text("\n".join(lines), encoding="utf-8")
    written.append(index_path)

    return written


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--feature", required=True, help="Path to feature spec markdown/text")
    ap.add_argument("--c4", required=True, help="Path to C4 model markdown/text")
    ap.add_argument("--out", required=True, help="Output directory for tasks")
    ap.add_argument("--milestone", default="MVP", help="Milestone label embedded into tasks")
    ap.add_argument("--prefix", default="XS", help="Story prefix (default: XS)")
    ap.add_argument("--candidates", type=int, default=5, help="Number of candidate decomposition plans to sample")
    ap.add_argument("--k", type=int, default=3, help="First-to-ahead-by-k margin for selecting a plan")
    ap.add_argument("--judge-calls", type=int, default=9, help="Max judge calls while selecting the best plan")
    ap.add_argument("--judge-backend", default="claude", choices=["claude", "codex"], help="Judge backend")
    ap.add_argument("--max-task-attempts", type=int, default=3, help="Retries per task markdown generation")
    args = ap.parse_args()

    feature_text = Path(args.feature).read_text(encoding="utf-8")
    c4_text = Path(args.c4).read_text(encoding="utf-8")
    out_dir = Path(args.out)

    if not have_cmd("claude"):
        print("Error: 'claude' CLI is required on PATH.", file=sys.stderr)
        return 2

    # 1) sample candidate plans
    candidates: List[Dict[str, Any]] = []
    plan_prompt = build_plan_prompt(feature_text, c4_text, args.milestone)

    for i in range(args.candidates):
        try:
            raw = run_claude(plan_prompt)
            plan = must_json(raw)
            # basic shape check
            if "tasks" not in plan or not isinstance(plan["tasks"], list) or len(plan["tasks"]) == 0:
                continue
            candidates.append(plan)
        except Exception:
            continue

    if len(candidates) < 1:
        print("Error: failed to generate any valid decomposition plans.", file=sys.stderr)
        return 3

    # 2) pick best plan via voting
    best = pick_best_plan(candidates, k=args.k, judge_calls=args.judge_calls, judge_backend=args.judge_backend)

    # 3) convert to blueprints
    try:
        milestone, blueprints, global_context = to_blueprints(best)
    except Exception as e:
        print(f"Error: chosen plan invalid: {e}", file=sys.stderr)
        return 4

    # minimal global context fallback
    if not global_context.strip():
        global_context = f"Milestone: {milestone}\nFeature: {Path(args.feature).stem}\n\nC4 model and feature spec define the architecture and contracts."

    # 4) render per-task markdown via Claude
    written = render_tasks(
        out_dir=out_dir,
        story_prefix=args.prefix,
        milestone=milestone,
        feature_text=feature_text,
        c4_text=c4_text,
        global_context=global_context,
        blueprints=blueprints,
        max_task_attempts=args.max_task_attempts,
    )

    print("Generated task files:")
    for p in written:
        print(f"- {p}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

