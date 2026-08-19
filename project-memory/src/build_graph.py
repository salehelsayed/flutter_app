#!/usr/bin/env python3
"""Deterministic extractor: plan corpus + session memory -> project-memory graph.

Two passes, in this order and never the other way round:

  1. PLAN pass (v1, plan 381) over `Test-Flight-Improv/*-tdd-plan.md`.
  2. MEMORY pass (v2, plan 382) over the session-memory directory.

Every rule below is keyword/regex deterministic: no LLM, no embeddings, no
network. A rebuild is therefore free and drift-proof, which is the whole point
(BASELINE-RESULTS.md proved a curated snapshot goes stale in weeks).

THE PRECEDENCE RULE (plan 382, live-proven the day it was written): on
2026-08-17 five session memories were caught claiming plan statuses the plan
corpus refutes. Memory is the layer that goes stale, so the memory pass runs
strictly AFTER plan facts are finalized and may only ADD its own `MEMORY`/`NOTE`
nodes and edges out of them. It can never create or move a plan-pass fact, and
the only edge it may draw at a plan is `references`. TC-382-03 holds that line.

Extraction rules and the census that justifies them (2026-08-17, 269 files):

  Status header      259 files carry `^Status:`; 1 more carries the bullet form
                     `- **Status:** ...`; 10 are headerless -> `unknown`.
  Closure precedence In-file closure evidence OUTRANKS the header, because the
                     header is provably stale in both directions (377 reads
                     execution-ready while the plan is CLOSED at device tier;
                     212 was left awaiting-review deliberately). Statuses are
                     ranked and the strongest wins.
  Final Execution    92 files carry a `## Final Execution Verdict` heading, but
  Verdict            11 of those sections are placeholders ("(pending)",
                     "(pending execution)", "<pending execution>", "(to be
                     filled at execution)"). The heading alone is NOT evidence;
                     the section body must carry a completion token. Plan 259 is
                     the pin for that distinction.
  Supersession       `superseded by plan NN` appears in 3 files, but only ONE is
                     a real supersession (148's `## CLOSED — superseded by plan
                     327`). The other two are prose about *wording* being
                     superseded (231) and this plan's own spec text (381). The
                     seam is therefore restricted to markdown HEADING lines.
  Refuted findings   4 censused shapes: `- Refuted findings:` (items on the
                     following indented lines OR inline after the colon),
                     `- Refuted findings (do NOT re-introduce):`,
                     `- **Refuted findings (do NOT re-introduce):**`, and
                     `### Refuted findings (do NOT re-introduce)` whose items
                     are TABLE ROWS (plan 315), not bullets.
  Deferred owners    `→ owner:` lines (13 across 4 files) and `Deferred device
                     work:` lines (61 files) -- but the majority of the latter
                     read "none.", and a `→ owner:` occurrence inside backticks
                     is documentation of the syntax, not a deferral. Both are
                     skipped: a placeholder must never become a fact.

Memory-pass rules and the census that justifies them (2026-08-17, 65 files):

  Corpus             64 fact files + the generated `MEMORY.md` index, which has
                     no frontmatter and is a table of contents, not a fact. It
                     is skipped and reported.
  Node shape         Two nodes per file: a short `MEMORY` node named by the
                     frontmatter `name`, and a `NOTE` node carrying the
                     description, joined by `asserts`. Recall echoes both
                     endpoint names on every edge line, so folding the
                     description into the MEMORY name made a single memory seed
                     cost ~920 of a 700-token budget and knocked a plan-381 gate
                     row out of its own answer. The split is a budget decision,
                     measured, not a taxonomy preference.
  Frontmatter        64/64 carry `name` + `description` + `metadata.type`
                     (project 49 / feedback 9 / reference 6). 57/64 carry
                     `metadata.modified`; the other 7 fall back to the file's
                     mtime date, which is machine-local -- and so is graph.db.
  Staleness markers  Case-SENSITIVE, for the same reason the plan pass keeps its
                     closed tier case-sensitive: `superseded`/`supersession` in
                     prose is history being described, not a marker on the
                     memory that describes it. 2 files carry `SUPERSEDED`; 5
                     carry `CORRECTED`/`STATUS CORRECTED`/`**Corrected`. Code
                     spans and fenced blocks are stripped before the scan, so a
                     memory documenting the marker VOCABULARY does not stale
                     itself -- the same carve-out as the plan pass's backticked
                     `→ owner:`, and project-memory-recall-layer is the live pin
                     that needs both it and the lowercase rule (relay-ec2-
                     deployment is the second lowercase pin).
  Wiki links         106 `[[target]]` occurrences over 46 distinct targets, 44
                     of which resolve. The 2 that do not (`skill-invocation-
                     policy`, a path) are counted and printed, never invented.
  Plan mentions      `plan NNN` plus bare 3-digit numbers in name+description.
                     A number written as an APPROXIMATION (`~150 test closures`)
                     is prose about magnitude, not a plan reference -- the same
                     carve-out as the plan pass's backticked `→ owner:`. Numbers
                     with no plan in the corpus (`uid 501`) are reported, never
                     invented. 18 edges resolve today.
"""

import argparse
import datetime as dt
import hashlib
import os
import re
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

CORPUS_GLOB = "*-tdd-plan.md"
SCHEMA_PATH = Path(__file__).resolve().parent / "schema.sql"
DEFAULT_CORPUS = Path(__file__).resolve().parents[2] / "Test-Flight-Improv"
DEFAULT_DB = Path(__file__).resolve().parents[1] / "graph.db"
DEFAULT_FLOOR = 250
# Account-scoped and OUTSIDE the repository by design: other machines, CI
# containers and Codex do not have it. An absent directory is tolerated (the
# graph is then byte-identical to a plan-only build), never fatal -- TC-382-05.
DEFAULT_MEMORY_DIR = Path("/claude-home/.claude/projects/-workspace/memory")
MEMORY_INDEX = "MEMORY.md"

MAX_NAME = 140
MAX_GAP_DESC = 100
MAX_OWNER = 100
# Recall renders BOTH endpoint names on every edge line, so a long entity name
# is paid many times over inside a 700-token budget. Measured 2026-08-17: with
# the description folded into the MEMORY name, one memory seed consumed ~920 of
# 700 tokens and pushed Q11's `[FINDING/refuted]` line out of the answer. The
# description therefore lives on its own NOTE node (short-named MEMORY nodes
# keep memory<->memory edges cheap) and is capped. 59 of 64 live descriptions
# are shorter than this cap; the longest is 346.
MAX_MEMORY_DESC = 200

# --------------------------------------------------------------------------
# Status vocabulary (QUESTIONS.md) + strength ranking. The ranking is what
# implements "closure evidence outranks a stale-open header": the strongest
# available signal wins, so a header can never downgrade a proven closure.
# --------------------------------------------------------------------------

STATUS_RANK = {
    "unknown": 0,
    "unnormalized": 1,
    "proposed": 2,
    "open": 2,
    "execution-ready": 3,
    "deferred": 3,
    "executed": 4,
    "closed": 5,
    "refuted": 5,
    "superseded": 6,
}

# Ordered rule table. First matching row wins; order is load-bearing
# ("execution-ready (NOT executed — queued behind 322/323)" must not read as
# executed, and "**SUPERSEDED / NOT EXECUTED**" must not either).
STATUS_RULES = [
    ("superseded", ("superseded",)),
    ("refuted", ("dropped", "refuted")),
    ("execution-ready", ("execution-ready", "execution ready")),
    ("closed", ("closed", "device-green", "device-proven")),
    ("executed", (
        "implemented",
        "executed",
        "execution_completed",
        "plan-green",
        "completed",
        "complete",
        "accepted",
        "host-green",
    )),
    ("proposed", ("awaiting-review", "reviewed", "planned", "proposed")),
]

STATUS_HEADER = re.compile(r"^Status:[ \t]*(?P<raw>.*)$")
STATUS_BULLET = re.compile(r"^[ \t]*[-*][ \t]+\*\*Status:?\*\*:?[ \t]*(?P<raw>.*)$")

PLAN_CLOSED = re.compile(r"\bPLAN\s+(\d+)\s+CLOSED\b")
HEADING = re.compile(r"^#{1,6}[ \t]+")
HEADING_CLOSED = re.compile(r"^#{1,6}[ \t]+.*\bCLOSED\b")
# Terminal-verdict sections, censused 2026-08-17: "Final Execution Verdict" x92,
# "Execution Result" x11 (+ "Final Execution Result" x2), "Execution Verdict",
# "Final verdict", "Current Execution Closure". Sections explicitly marked
# Historical/Prior are excluded -- they are superseded content inside the doc.
VERDICT_HEADING = re.compile(
    r"^#{1,6}[ \t]+(?!.*\b(?:historical|prior)\b)"
    r".*\b(?:final execution verdict|execution result|execution verdict"
    r"|final verdict|execution closure)\b",
    re.I,
)
# Uppercase CLOSED is how this corpus states plan closure ("**CLOSED 2026-08-01.**",
# "PLAN 377 CLOSED"). Matching it case-insensitively would catch prose about
# blockers being "closed in source", so the closed tier stays case-sensitive.
VERDICT_CLOSED = re.compile(r"\bCLOSED\b|\bDEVICE-GREEN\b|\bDEVICE-PROVEN\b")
VERDICT_EXECUTED = re.compile(
    r"\bEXECUTED\b|\bIMPLEMENTED\b|\bACCEPTED\b|host-green|plan-green|device-proven",
    re.I,
)
SUPERSEDED_BY = re.compile(r"superseded by plan[ \t]+(\d+)", re.I)

REFUTED_BULLET = re.compile(
    r"^(?P<indent>[ \t]*)[-*][ \t]+\*{0,2}Refuted findings\b(?P<qualifier>[^:\n]*):"
    r"\*{0,2}[ \t]*(?P<rest>.*)$",
    re.I,
)
REFUTED_HEADING = re.compile(r"^#{1,6}[ \t]+\*{0,2}Refuted findings\b", re.I)
LIST_ITEM = re.compile(r"^[ \t]*[-*][ \t]+")
TABLE_ROW = re.compile(r"^[ \t]*\|")
TABLE_SEPARATOR = re.compile(r"^[ \t]*\|[\s:|-]+\|?[ \t]*$")

OWNER_ARROW = re.compile(r"→[ \t]*owner:[ \t]*")
DEFERRED_DEVICE = re.compile(
    r"^[ \t]*[-*]?[ \t]*\*{0,2}Deferred device work\*{0,2}[ \t]*:[ \t]*(?P<value>.*)$",
    re.I,
)
PLACEHOLDER = re.compile(
    r"^(n/?a|none|tbd|todo|pending|—|-|\.|\(pending[^)]*\)|<pending[^>]*>)\.?$", re.I
)

PLAN_NUMBER = re.compile(r"^(\d+)-")
TITLE_TOKEN = re.compile(r"[a-z0-9]+")
# Hyphenated compounds are how this corpus names its concepts ("state-guard",
# "empty-nomination", "multi-device"). They are aliased verbatim so a question
# phrased the same way seeds directly instead of relying on traversal.
COMPOUND = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)+")

# --------------------------------------------------------------------------
# Memory pass (plan 382)
# --------------------------------------------------------------------------

FRONTMATTER = re.compile(r"\A---[ \t]*\r?\n(?P<front>.*?)\r?\n---[ \t]*\r?$", re.S | re.M)
FM_NAME = re.compile(r"^name:[ \t]*(?P<value>.+)$", re.M)
FM_DESCRIPTION = re.compile(r"^description:[ \t]*(?P<value>.+)$", re.M)
FM_TYPE = re.compile(r"^[ \t]+type:[ \t]*(?P<value>.+)$", re.M)
FM_MODIFIED = re.compile(r"^[ \t]+modified:[ \t]*(?P<value>.+)$", re.M)

# Case-sensitive on purpose -- see the census note in the module docstring.
MEMORY_SUPERSEDED = re.compile(r"\bSUPERSEDED\b")
MEMORY_CORRECTED = re.compile(r"\bCORRECTED\b|^\*{0,2}Corrected\b", re.M)
FENCED_CODE = re.compile(r"```.*?```", re.S)
INLINE_CODE = re.compile(r"`[^`\n]*`")
WIKI_LINK = re.compile(r"\[\[([^\[\]]+)\]\]")
# `plan NNN` in any casing, or a bare 3-digit number that is not an
# approximation (`~150`) and not part of a longer word or a percentage.
MEMORY_PLAN_REF = re.compile(r"\bplans?[ \t-]+(\d{2,4})\b|(?<![~$\w])(\d{3})(?![\w%])", re.I)
# Underscores are PRESERVED: screaming-snake flag names
# (DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED) are exactly the anchors a
# question carries verbatim, and recall.py's tokenizer keeps them too.
MEMORY_TOKEN = re.compile(r"[a-z0-9][a-z0-9_./-]*")
ISO_DATE = re.compile(r"^(\d{4}-\d{2}-\d{2})")


class BuildReport(object):
    """Census of one build. Printed in full: no silent truncation anywhere."""

    def __init__(self):
        self.parsed = 0
        self.skipped = []
        self.unnormalized = []
        self.unresolved_supersession = []
        self.entities = 0
        self.relations = 0
        self.floor = 0
        self.floor_satisfied = True
        # Memory pass (plan 382). `memory_requested` stays False when no memory
        # directory was asked for at all, so a plan-only build prints exactly
        # what it printed under plan 381.
        self.memory_requested = False
        self.memory_absent = False
        self.memory_parsed = 0
        self.memory_skipped = []
        self.memory_unresolved_links = []
        self.memory_unresolved_plans = []

    def render(self):
        lines = [
            "parsed: {}".format(self.parsed),
            "entities: {}  relations: {}".format(self.entities, self.relations),
            "floor: {} ({})".format(
                self.floor, "satisfied" if self.floor_satisfied else "VIOLATED"
            ),
            "skipped: {}".format(len(self.skipped)),
        ]
        for item in self.skipped:
            lines.append("  skip {} -- {}".format(item[0], item[1]))
        lines.append("unnormalized: {}".format(len(self.unnormalized)))
        for doc, raw in self.unnormalized:
            lines.append("  unnormalized {} -- {!r}".format(doc, raw[:80]))
        lines.append("unresolved supersession: {}".format(len(self.unresolved_supersession)))
        for doc, number in self.unresolved_supersession:
            lines.append("  unresolved {} -> plan {}".format(doc, number))
        lines.extend(self._memory_lines())
        return "\n".join(lines)

    def _memory_lines(self):
        if not self.memory_requested:
            return []
        if self.memory_absent:
            return ["memory source absent (0 files)"]
        lines = [
            "memory: {} parsed".format(self.memory_parsed),
            "memory skipped: {}".format(len(self.memory_skipped)),
        ]
        for name, reason in self.memory_skipped:
            lines.append("  skip {} -- {}".format(name, reason))
        lines.append("memory unresolved links: {}".format(len(self.memory_unresolved_links)))
        for source, target in self.memory_unresolved_links:
            lines.append("  unresolved link {} -> {}".format(source, target))
        lines.append(
            "memory unresolved plan refs: {}".format(len(self.memory_unresolved_plans)))
        for source, number in self.memory_unresolved_plans:
            lines.append("  unresolved plan {} -> {}".format(source, number))
        return lines


# --------------------------------------------------------------------------
# Provenance
# --------------------------------------------------------------------------

def _git(root, *args):
    try:
        out = subprocess.run(
            ["git", "-C", str(root)] + list(args),
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    return out.stdout.decode("utf-8", "replace").strip()


def provenance(corpus_dir):
    """(head sha, commit date, dirty-path set). Deterministic for a given tree."""
    head = _git(corpus_dir, "rev-parse", "--short", "HEAD")
    if head is None:
        return "no-git", "no-git", set()
    built_at = _git(corpus_dir, "show", "-s", "--format=%cI", "HEAD") or "no-git"
    dirty = set()
    porcelain = _git(corpus_dir, "status", "--porcelain", "--untracked-files=all", "--", ".")
    if porcelain:
        for line in porcelain.splitlines():
            if len(line) > 3:
                dirty.add(line[3:].strip().strip('"'))
    return head, built_at, dirty


# --------------------------------------------------------------------------
# Parsing helpers
# --------------------------------------------------------------------------

def normalize_status(raw):
    """Total function: every raw header maps to a vocabulary term."""
    if raw is None:
        return "unknown"
    text = raw.strip().lower()
    if not text:
        return "unnormalized"
    for status, keywords in STATUS_RULES:
        for keyword in keywords:
            if keyword in text:
                return status
    return "unnormalized"


def clean_text(text):
    text = text.strip()
    text = re.sub(r"\s+", " ", text)
    text = text.strip("*").strip()
    text = re.sub(r"^[-*•]\s*", "", text)
    return text.strip()


def truncate(text, limit):
    if len(text) <= limit:
        return text
    return text[:limit].rstrip()


def is_placeholder(text):
    stripped = clean_text(text).strip("_`")
    return not stripped or bool(PLACEHOLDER.match(stripped))


def alias_tokens(text, minimum):
    lowered = text.lower()
    found = {token for token in TITLE_TOKEN.findall(lowered) if len(token) >= minimum}
    found.update(COMPOUND.findall(lowered))
    return sorted(found)


def plan_aliases(stem):
    aliases = {stem.lower()}
    title = re.sub(r"-tdd-plan$", "", stem)
    match = PLAN_NUMBER.match(stem)
    if match:
        number = match.group(1)
        aliases.update({number, "plan {}".format(number), "plan-{}".format(number)})
        title = title[len(number) + 1:]
    aliases.add(title.lower())
    words = [word for word in title.lower().split("-") if word]
    aliases.update(word for word in words if len(word) >= 4)
    aliases.update(
        "{}-{}".format(words[index], words[index + 1]) for index in range(len(words) - 1)
    )
    return sorted(alias for alias in aliases if alias)


def find_status_header(lines):
    for number, line in enumerate(lines, start=1):
        match = STATUS_HEADER.match(line)
        if match:
            return match.group("raw"), number
    for number, line in enumerate(lines, start=1):
        match = STATUS_BULLET.match(line)
        if match:
            return match.group("raw"), number
    return None, 1


def closure_evidence(lines, own_number):
    """Strongest in-file closure signal, or None.

    `PLAN <n> CLOSED` only counts when <n> is this plan's own number -- plans
    routinely quote other plans' closure lines (and this plan's own spec quotes
    the regex itself).
    """
    for number, line in enumerate(lines, start=1):
        for cited in PLAN_CLOSED.findall(line):
            if own_number and cited == own_number:
                return "closed", number
        if HEADING_CLOSED.match(line):
            return "closed", number

    # A verdict HEADING is not evidence on its own: 11 of the 92 sections are
    # placeholders ("(pending)", "<pending execution>", "(to be filled at
    # execution)"). Plan 259 is the pin. The body must actually say something.
    best = (None, 0)
    for index, line in enumerate(lines):
        if not VERDICT_HEADING.match(line):
            continue
        body = []
        for follower in lines[index + 1:]:
            if HEADING.match(follower):
                break
            body.append(follower)
        text = "\n".join(body)
        # The closed tier reads only the verdict's OPENING line, because that is
        # where this corpus states plan closure ("**CLOSED 2026-08-01.**",
        # "Verdict: **CLOSED (host-only, 2026-07-06)**", "**CLOSED, host tier.**").
        # Deeper in the same section, "CLOSED" is about bugs or contract rows --
        # plan 135's "all 6 bugs CLOSED host-side" is the pin for that.
        opening = next((item for item in body if item.strip()), "")
        found = None
        if VERDICT_CLOSED.search(opening):
            found = "closed"
        elif VERDICT_EXECUTED.search(text):
            found = "executed"
        if found and (best[0] is None or STATUS_RANK[found] > STATUS_RANK[best[0]]):
            best = (found, index + 1)
    return best


def block_items(lines, start_index):
    """Items of a refuted-findings block, as (text, line_number) pairs."""
    header = lines[start_index]
    items = []

    bullet = REFUTED_BULLET.match(header)
    if bullet:
        rest = bullet.group("rest")
        if rest.strip() and not is_placeholder(rest):
            items.append([rest, start_index + 1])
        indent = len(bullet.group("indent"))
        for offset in range(start_index + 1, len(lines)):
            line = lines[offset]
            if not line.strip():
                break
            stripped = len(line) - len(line.lstrip())
            if stripped <= indent:
                break
            if LIST_ITEM.match(line):
                items.append([line.strip(), offset + 1])
            elif items:
                items[-1][0] += " " + line.strip()
        return items

    table = []
    for offset in range(start_index + 1, len(lines)):
        line = lines[offset]
        if HEADING.match(line):
            break
        if TABLE_ROW.match(line):
            table.append((line, offset + 1))
        elif LIST_ITEM.match(line):
            items.append([line.strip(), offset + 1])
        elif items and line.strip():
            items[-1][0] += " " + line.strip()

    separator = next(
        (index for index, (line, _) in enumerate(table) if TABLE_SEPARATOR.match(line)),
        None,
    )
    rows = table[separator + 1:] if separator is not None else table
    for line, number in rows:
        cells = [cell for cell in line.strip().strip("|").split("|")]
        if cells:
            items.append([cells[0], number])
    return items


def owner_split(line):
    """(description, owner) for a real `→ owner:` deferral, else None.

    An occurrence wrapped in backticks is documentation of the syntax (this
    plan's own spec text does exactly that), never a deferral.
    """
    for match in OWNER_ARROW.finditer(line):
        before = line[:match.start()].rstrip()
        if before.endswith("`"):
            continue
        owner = line[match.end():].strip()
        if not before.strip() or is_placeholder(owner):
            continue
        return clean_text(before), clean_text(owner)
    return None


# --------------------------------------------------------------------------
# Memory-pass helpers
# --------------------------------------------------------------------------

def frontmatter_value(raw):
    """One scalar frontmatter value, unquoted."""
    value = raw.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1]
    return value.strip()


def mtime_date(path):
    """UTC date of a file's mtime. The stated fallback when `modified:` is absent.

    Machine-local, and accepted as such: graph.db is machine-local too, and the
    alternative -- a null date on 7 of 64 facts -- would break the "every fact
    carries a date" rule the whole ontology rests on.
    """
    stamp = dt.datetime.fromtimestamp(Path(path).stat().st_mtime, dt.timezone.utc)
    return stamp.strftime("%Y-%m-%d")


def strip_code(text):
    """Text with fenced blocks and inline code spans removed.

    A marker inside backticks is documentation of the vocabulary, not a marker
    on the memory that documents it -- the same carve-out `owner_split` makes
    for a backticked `→ owner:`. Live pin: `project-memory-recall-layer`
    describes the `SUPERSEDED`/`CORRECTED` rule and must stay `active`.
    """
    text = FENCED_CODE.sub(" ", text)
    return INLINE_CODE.sub(" ", text)


def memory_status(text):
    """(status, marker) from the case-sensitive staleness markers."""
    scannable = strip_code(text)
    match = MEMORY_SUPERSEDED.search(scannable)
    if match:
        return "superseded", match.group(0)
    match = MEMORY_CORRECTED.search(scannable)
    if match:
        return "corrected", match.group(0).lstrip("*")
    return "active", ""


def memory_slug_aliases(slug):
    """Slug parts (>=4 chars) + adjacent pairs, mirroring `plan_aliases`.

    The pairs are load-bearing: recall probes a question's raw hyphenated token
    (`per-plan`, `delete-ack`) before it probes the parts.
    """
    lowered = slug.lower()
    words = [word for word in re.split(r"[-_/]", lowered) if word]
    aliases = {lowered}
    aliases.update(word for word in words if len(word) >= 4)
    aliases.update(
        "{}-{}".format(words[index], words[index + 1]) for index in range(len(words) - 1)
    )
    return sorted(alias for alias in aliases if alias)


def memory_alias_tokens(text, minimum):
    """Description tokens, underscores and slashes preserved.

    `alias_tokens` splits on every non-alphanumeric, which would shred
    `DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED` into eight useless words and
    `test/unit` into two. Recall's tokenizer keeps both shapes, so this one does
    too -- plus the parts, because recall probes those as well.
    """
    lowered = text.lower()
    found = set()
    for raw in MEMORY_TOKEN.findall(lowered):
        token = raw.strip("./-_")
        if not token:
            continue
        if len(token) >= minimum:
            found.add(token)
        for part in re.split(r"[/-]", token):
            if len(part) >= minimum:
                found.add(part)
    found.update(COMPOUND.findall(lowered))
    return sorted(found)


def memory_plan_numbers(text):
    """Plan numbers referenced by a memory's name + description."""
    numbers = set()
    for explicit, bare in MEMORY_PLAN_REF.findall(text):
        numbers.add(explicit or bare)
    return sorted(numbers)


def read_memory(path):
    """Parsed memory file, or (None, reason)."""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as error:
        return None, "unreadable: {}".format(error)
    block = FRONTMATTER.match(text)
    if not block:
        return None, "no frontmatter block"
    front = block.group("front")
    name_match = FM_NAME.search(front)
    if not name_match:
        return None, "frontmatter has no name"
    slug = frontmatter_value(name_match.group("value"))
    if not slug:
        return None, "frontmatter name is empty"

    description_match = FM_DESCRIPTION.search(front)
    description = (
        frontmatter_value(description_match.group("value")) if description_match else ""
    )
    type_match = FM_TYPE.search(front)
    mtype = frontmatter_value(type_match.group("value")) if type_match else "unknown"
    modified_match = FM_MODIFIED.search(front)
    updated = None
    if modified_match:
        stamp = ISO_DATE.match(frontmatter_value(modified_match.group("value")))
        if stamp:
            updated = stamp.group(1)
    if updated is None:
        updated = mtime_date(path)

    status, marker = memory_status(text)
    links = []
    for number, line in enumerate(text.splitlines(), start=1):
        for target in WIKI_LINK.findall(line):
            links.append((target.strip(), number))
    return {
        "slug": slug,
        "description": description,
        "type": mtype,
        "updated": updated,
        "status": status,
        "marker": marker,
        "links": links,
        "path": path,
    }, None


def memory_pass(memory_dir, plans_by_number, head, report):
    """Second pass: session memory -> MEMORY/NOTE entities + edges. Nothing else.

    Returns (entities, relations, aliases, updated_by_id). It is handed the
    plan index read-only and never returns a plan row: that is the precedence
    rule, and TC-382-03 is the test that proves it holds.

    Shape: each file becomes a SHORT `MEMORY` node named by its frontmatter
    `name`, plus a `NOTE` node carrying the description, joined by `asserts`.
    Splitting them is what keeps memory affordable inside recall's budget -- see
    MAX_MEMORY_DESC for the measurement that forced it.
    """
    report.memory_requested = True
    memory_dir = Path(memory_dir)
    if not memory_dir.is_dir():
        report.memory_absent = True
        return [], [], [], {}

    records = []
    for path in sorted(memory_dir.glob("*.md"), key=lambda item: item.name):
        if path.name == MEMORY_INDEX:
            report.memory_skipped.append((path.name, "generated index (no frontmatter)"))
            continue
        record, reason = read_memory(path)
        if record is None:
            report.memory_skipped.append((path.name, reason))
            continue
        records.append(record)

    by_slug = {record["slug"]: "memory:{}".format(record["slug"]) for record in records}

    entities = []
    relations = []
    aliases = []
    updated_by_id = {}

    for record in records:
        slug = record["slug"]
        memory_id = by_slug[slug]
        doc = str(record["path"].resolve())
        # Provenance for a fact that lives OUTSIDE git: the build stamp plus the
        # source's own recency, so a memory fact can never be read detached from
        # how old it is. Same shape as the plan pass's `+worktree` suffix.
        commit = "{}+mem:{}".format(head, record["updated"])
        description = truncate(clean_text(record["description"]), MAX_MEMORY_DESC)
        status_raw = "type:{}".format(record["type"])
        if record["marker"]:
            status_raw += " || marker:{}".format(record["marker"])

        entities.append((
            memory_id, slug, "MEMORY", record["status"], status_raw, doc, 1, commit,
        ))
        updated_by_id[memory_id] = record["updated"]
        report.memory_parsed += 1
        for alias in memory_slug_aliases(slug):
            aliases.append((alias, memory_id))

        # The description is a fact in its own right, and the one a question is
        # usually phrased against ("why must /workspace never be stashed"). It
        # is aliased to the NOTE so a description-phrased question seeds the
        # text that answers it, and the `states` edge carries both on one line.
        if description:
            note_id = "note:{}".format(slug)
            entities.append((
                note_id, description, "NOTE", record["status"], status_raw, doc, 1, commit,
            ))
            updated_by_id[note_id] = record["updated"]
            # `asserts` sorts before every other rtype, and recall breaks
            # equal-relevance edge ties on rtype. A memory's own sentence must
            # therefore win the seed's first-pass slots against its
            # cross-references -- measured: without it, Q25's answer text lost
            # to four `references` edges and fell past the budget.
            relations.append((memory_id, note_id, "asserts", doc, 1))
            # Aliased to BOTH nodes: a description-phrased question must surface
            # the memory's own identity line (name, status, path, date) too, not
            # only the sentence -- otherwise the fact arrives without its
            # staleness marker.
            for alias in memory_alias_tokens(record["description"], 6):
                aliases.append((alias, note_id))
                aliases.append((alias, memory_id))

        # [[links]] -> MEMORY->MEMORY. An unresolved target is counted and
        # printed; a stub entity would be a fabricated fact.
        seen_links = set()
        for target, line in record["links"]:
            if target in seen_links:
                continue
            seen_links.add(target)
            destination = by_slug.get(target)
            if destination is None:
                report.memory_unresolved_links.append((slug, target))
                continue
            if destination == memory_id:
                continue
            relations.append((memory_id, destination, "references", doc, line))

        # Plan mentions -> MEMORY->PLAN. Edges only: a memory never carries a
        # plan's status, however confidently it claims to.
        for number in memory_plan_numbers("{} {}".format(slug, record["description"])):
            plan_id = plans_by_number.get(number)
            if plan_id is None:
                report.memory_unresolved_plans.append((slug, number))
                continue
            relations.append((memory_id, plan_id, "references", doc, 1))

    return entities, relations, aliases, updated_by_id


# --------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------

def _relative(path, corpus_dir):
    for base in (Path(__file__).resolve().parents[2], corpus_dir.parent):
        try:
            return str(path.resolve().relative_to(base.resolve()))
        except ValueError:
            continue
    return str(path)


def build(corpus_dir, db_path, floor=DEFAULT_FLOOR, memory_dir=None):
    """Plan pass, then (optionally) the memory pass. `memory_dir=None` builds a
    plan-only graph byte-identical to plan 381's."""
    corpus_dir = Path(corpus_dir)
    db_path = Path(db_path)
    report = BuildReport()
    report.floor = floor

    head, built_at, dirty = provenance(corpus_dir)
    entities = []       # (id, name, etype, status, status_raw, doc, line, commit)
    relations = []      # (src, dst, rtype, doc, line)
    aliases = []        # (alias, entity_id)
    plans_by_number = {}
    status_by_id = {}

    for path in sorted(corpus_dir.glob(CORPUS_GLOB), key=lambda item: item.name):
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError as error:
            report.skipped.append((path.name, "unreadable: {}".format(error)))
            continue
        if not text.strip():
            report.skipped.append((path.name, "empty file"))
            continue

        lines = text.splitlines()
        stem = path.stem
        doc = _relative(path, corpus_dir)
        commit = head + "+worktree" if doc in dirty else head
        plan_id = "plan:{}".format(stem)
        number_match = PLAN_NUMBER.match(stem)
        own_number = number_match.group(1) if number_match else None

        raw, status_line = find_status_header(lines)
        header_status = normalize_status(raw)
        status = header_status
        status_raw = raw if raw is not None else ""
        evidence_status, evidence_line = closure_evidence(lines, own_number)
        if evidence_status and STATUS_RANK[evidence_status] > STATUS_RANK[status]:
            status = evidence_status
            status_raw = "{} || closure-evidence:{}@{}".format(
                status_raw, evidence_status, evidence_line
            )
        if header_status == "unnormalized" and raw:
            report.unnormalized.append((doc, raw))

        entities.append((
            plan_id, re.sub(r"-tdd-plan$", "", stem), "PLAN", status,
            status_raw or "(no Status header)", doc, status_line, commit,
        ))
        status_by_id[plan_id] = status
        if own_number:
            plans_by_number[own_number] = plan_id
        for alias in plan_aliases(stem):
            aliases.append((alias, plan_id))
        report.parsed += 1

        # --- refuted findings -------------------------------------------------
        finding_index = 0
        for index, line in enumerate(lines):
            if not (REFUTED_BULLET.match(line) or REFUTED_HEADING.match(line)):
                continue
            for raw_item, item_line in block_items(lines, index):
                name = truncate(clean_text(raw_item), MAX_NAME)
                if not name or is_placeholder(name):
                    continue
                finding_index += 1
                finding_id = "finding:{}:{:03d}".format(stem, finding_index)
                entities.append((
                    finding_id, name, "FINDING", "refuted", "refuted finding",
                    doc, item_line, commit,
                ))
                relations.append((plan_id, finding_id, "refutes", doc, item_line))
                for token in alias_tokens(name, 6):
                    aliases.append((token, finding_id))

        # --- deferred items with owners --------------------------------------
        gap_index = 0
        for index, line in enumerate(lines):
            name = None
            split = owner_split(line)
            if split:
                description, owner = split
                name = "{} → owner: {}".format(
                    truncate(description, MAX_GAP_DESC), truncate(owner, MAX_OWNER)
                )
            else:
                device = DEFERRED_DEVICE.match(line)
                if device and not is_placeholder(device.group("value")):
                    name = "Deferred device work: {}".format(
                        truncate(clean_text(device.group("value")), MAX_GAP_DESC)
                    )
            if not name:
                continue
            gap_index += 1
            gap_id = "gap:{}:{:03d}".format(stem, gap_index)
            entities.append((
                gap_id, name, "GAP", "deferred", "deferred item", doc, index + 1, commit,
            ))
            relations.append((plan_id, gap_id, "deferred_to", doc, index + 1))
            for token in alias_tokens(name, 6):
                aliases.append((token, gap_id))

        # --- supersession (heading lines only) --------------------------------
        for index, line in enumerate(lines):
            if not HEADING.match(line):
                continue
            for cited in SUPERSEDED_BY.findall(line):
                if cited == own_number:
                    continue
                relations.append(("PENDING:{}".format(cited), plan_id, "supersedes",
                                  doc, index + 1))

    # Resolve supersession once every plan entity exists (anti-fabrication: an
    # edge to a plan outside the corpus is reported, never invented).
    resolved = []
    for src, dst, rtype, doc, line in relations:
        if src.startswith("PENDING:"):
            number = src.split(":", 1)[1]
            target = plans_by_number.get(number)
            if target is None:
                report.unresolved_supersession.append((doc, number))
                continue
            resolved.append((target, dst, rtype, doc, line))
            status_by_id[dst] = "superseded"
        else:
            resolved.append((src, dst, rtype, doc, line))
    relations = resolved

    entities = [
        (row[0], row[1], row[2], status_by_id.get(row[0], row[3])) + row[4:]
        for row in entities
    ]

    # --- memory pass -------------------------------------------------------
    # Deliberately here, after every plan fact is final. `status_by_id` is not
    # in scope for the memory pass, so no memory can reach a plan's status even
    # by accident -- the leak would have to be written on purpose.
    updated_by_id = {}
    if memory_dir is not None:
        memory_entities, memory_relations, memory_aliases, updated_by_id = memory_pass(
            memory_dir, plans_by_number, head, report
        )
        entities = entities + memory_entities
        relations = relations + memory_relations
        aliases = aliases + memory_aliases

    report.entities = len(entities)
    report.relations = len(set(relations))
    report.floor_satisfied = report.parsed >= floor

    _write(db_path, entities, relations, aliases, updated_by_id, built_at)
    return report


def _write(db_path, entities, relations, aliases, updated_by_id, built_at):
    """Atomic tmp+rename write; sorted inserts keep rebuilds byte-stable."""
    db_path = Path(db_path)
    db_path.parent.mkdir(parents=True, exist_ok=True)
    handle, tmp_name = tempfile.mkstemp(
        prefix=".{}.".format(db_path.name), dir=str(db_path.parent)
    )
    os.close(handle)
    os.unlink(tmp_name)
    connection = sqlite3.connect(tmp_name)
    try:
        connection.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))
        connection.executemany(
            "INSERT OR REPLACE INTO entities"
            " (id, name, etype, status, status_raw, source_doc, source_line,"
            "  source_commit, updated_date, built_at)"
            " VALUES (?,?,?,?,?,?,?,?,?,?)",
            # `updated_date` is joined here rather than carried in the tuple so
            # the sort key stays the plan-381 8-tuple of non-null strings/ints.
            [row + (updated_by_id.get(row[0]), built_at)
             for row in sorted(set(entities))],
        )
        connection.executemany(
            "INSERT OR REPLACE INTO relations"
            " (src_id, dst_id, rtype, source_doc, source_line) VALUES (?,?,?,?,?)",
            sorted(set(relations)),
        )
        connection.executemany(
            "INSERT OR REPLACE INTO aliases (alias, entity_id) VALUES (?,?)",
            sorted(set(aliases)),
        )
        connection.commit()
    finally:
        connection.close()
    os.replace(tmp_name, str(db_path))


# --------------------------------------------------------------------------
# Read helpers (shared by recall.py, run_eval.py and the contract suite)
# --------------------------------------------------------------------------

def query(db_path, sql, params=()):
    connection = sqlite3.connect("file:{}?mode=ro".format(db_path), uri=True)
    try:
        return list(connection.execute(sql, params))
    finally:
        connection.close()


def content_hash(db_path):
    """Hash of the graph CONTENT (row-ordered), not of sqlite's page layout."""
    digest = hashlib.sha256()
    for table, order in (
        ("entities", "id"),
        ("relations", "src_id, dst_id, rtype, source_doc, source_line"),
        ("aliases", "alias, entity_id"),
    ):
        digest.update(table.encode("utf-8"))
        for row in query(db_path, "SELECT * FROM {} ORDER BY {}".format(table, order)):
            digest.update(repr(row).encode("utf-8"))
    return digest.hexdigest()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--corpus", default=str(DEFAULT_CORPUS))
    parser.add_argument("--db", default=str(DEFAULT_DB))
    parser.add_argument("--floor", type=int, default=DEFAULT_FLOOR)
    parser.add_argument(
        "--memory-dir", default=str(DEFAULT_MEMORY_DIR),
        help="session-memory directory; an absent path is tolerated (0 files)",
    )
    args = parser.parse_args(argv)

    report = build(Path(args.corpus), Path(args.db), floor=args.floor,
                   memory_dir=Path(args.memory_dir))
    print(report.render())
    if not report.floor_satisfied:
        print(
            "FAIL: parsed {} < floor {} -- the corpus glob or the parser regressed"
            .format(report.parsed, report.floor),
            file=sys.stderr,
        )
        return 1
    print("OK: graph written to {}".format(args.db))
    return 0


if __name__ == "__main__":
    sys.exit(main())
