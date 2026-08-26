#!/usr/bin/env python3
"""Patch graphify's Dart extractor (extract.py) and entity dedup (dedup.py).

Fixes three gaps that hurt this repo's graphs (probed 2026-06-12, graphifyy 0.8.33):
  1. Dart nodes get no source_location (Go nodes do) — and the comment stripper
     deletes newlines inside /* */ blocks, which would skew any line counting.
  2. Two declaration shapes are never captured:
     a. multi-line signatures (return type on its own line, e.g.
        `Future<(A, B, C)>\nhandleIncomingChatMessage({`)
     b. nested local functions (indent >= 3, e.g. the helpers inside
        `downloadMedia`: verifyCommittedLocalPath, deleteFailedDownloadArtifacts,
        adoptCanonicalFileIfAvailable).
  3. dedup.py Pass-2 fuzzy matching merges DIFFERENTLY-NAMED code symbols whose
     names are string-similar (Jaro-Winkler on a long shared prefix), silently
     deleting real declarations: dbMarkInboxStagingEntryRetryable was absorbed
     into dbMarkInboxStagingEntryRejected, recoverIdentityFromSecureStore into
     its own file node. Code identifiers are exact — different name, different
     symbol. v2 (2026-07-18) blocks different-label fuzzy merges for EVERY node
     type: this repo's doc corpus uses systematic IDs (GK-011 vs GK-012 plans)
     that fuzzy-match, and cross-label merging makes dedup non-idempotent —
     graph.json shrank on every cluster-only load and labels churned.

Idempotent: marker comments are written into the patched files; re-running is a
no-op. Re-apply after any `uv tool upgrade graphifyy` (the upgrade wipes it) —
refresh_arch_graph.sh runs this script automatically. After applying, clear the
AST cache (keyed by file hash only, NOT extractor version — stale results
survive otherwise):
    rm -rf graphify-out/cache/ast
then rebuild: ./graphify-arch/refresh_arch_graph.sh (arch) and re-extract the
full graph's Dart files.

Layout note (re-derived 2026-07-18 against graphifyy 0.9.18): upstream moved
the per-language extractors out of extract.py into graphify/extractors/
(dart.py, go.py, ...) verbatim — every anchor below still matches, only the
target files moved. This script resolves both layouts: extractors/dart.py and
extractors/go.py when present, monolithic extract.py otherwise.
"""

import importlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

MARKER = "MKNOON-PATCH dart-linenos v1"
MARKER_V2 = "MKNOON-PATCH dart-artifacts v2"
MARKER_V2_GO = "MKNOON-PATCH go-artifacts v2"
DEDUP_MARKER_V1 = "MKNOON-PATCH code-no-fuzzy v1"
DEDUP_MARKER = "MKNOON-PATCH no-fuzzy v2"


def _resolve_module_file(module: str) -> Path | None:
    try:
        return Path(importlib.import_module(module).__file__)
    except ImportError:
        pass
    bin_path = shutil.which("graphify")
    if not bin_path:
        return None
    shebang = Path(bin_path).read_text(errors="replace").splitlines()[0].lstrip("#!")
    out = subprocess.run(
        [shebang, "-c", f"import {module} as m; print(m.__file__)"],
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        return None
    return Path(out.stdout.strip())


def find_module_file(*candidates: str) -> Path:
    for module in candidates:
        path = _resolve_module_file(module)
        if path is not None:
            return path
    sys.exit(f"none of {candidates} importable via graphify's python")


EDITS = [
    # 1. Preserve line count when stripping /* */ comments.
    (
        '''    def _comment_replace(match: re.Match) -> str:
        token = match.group(0)
        if token.startswith("/"):
            return ""
        return token
    src_clean = comment_string_pattern.sub(_comment_replace, src)

    stem = _file_stem(path)
    file_nid = _make_id(str(path))''',
        '''    def _comment_replace(match: re.Match) -> str:
        token = match.group(0)
        if token.startswith("/"):
            # ''' + MARKER + ''': keep newlines so line numbers stay accurate
            return "\\n" * token.count("\\n")
        return token
    src_clean = comment_string_pattern.sub(_comment_replace, src)

    stem = _file_stem(path)
    file_nid = _make_id(str(path))''',
    ),
    # 2. add_node grows an optional line argument; helper computes lines.
    (
        '''    def add_node(nid: str, label: str, ftype: str = "code", source_file: str | None = str(path)) -> None:
        if nid not in defined:
            nodes.append({"id": nid, "label": label, "file_type": ftype,
                          "source_file": source_file, "source_location": None})
            defined.add(nid)

    def add_edge(src_id: str, tgt_id: str, relation: str, weight: float = 1.0, context: str | None = None) -> None:
        edge = {"source": src_id, "target": tgt_id, "relation": relation,
                "confidence": "EXTRACTED", "confidence_score": 1.0,
                "source_file": str(path), "source_location": None, "weight": weight}''',
        '''    def _line_of(pos: int) -> int:
        return src_clean.count("\\n", 0, pos) + 1

    def add_node(nid: str, label: str, ftype: str = "code", source_file: str | None = str(path), line: int | None = None) -> None:
        if nid not in defined:
            nodes.append({"id": nid, "label": label, "file_type": ftype,
                          "source_file": source_file,
                          "source_location": f"L{line}" if line else None})
            defined.add(nid)

    def add_edge(src_id: str, tgt_id: str, relation: str, weight: float = 1.0, context: str | None = None) -> None:
        edge = {"source": src_id, "target": tgt_id, "relation": relation,
                "confidence": "EXTRACTED", "confidence_score": 1.0,
                "source_file": str(path), "source_location": None, "weight": weight}''',
    ),
    # 3. Class/mixin/enum nodes get a line number.
    (
        '''        class_name = m.group(1)
        class_nid = _make_id(stem, class_name)
        add_node(class_nid, class_name)
        add_edge(file_nid, class_nid, "defines")''',
        '''        class_name = m.group(1)
        class_nid = _make_id(stem, class_name)
        add_node(class_nid, class_name, line=_line_of(m.start(1)))
        add_edge(file_nid, class_nid, "defines")''',
    ),
    # 4a. Top-level/class-level single variable nodes get a line number.
    (
        '''            if single_name not in {"if", "for", "while", "switch", "catch", "return"}:
                var_nid = _make_id(stem, single_name)
                add_node(var_nid, single_name)
                add_edge(file_nid, var_nid, "defines")''',
        '''            if single_name not in {"if", "for", "while", "switch", "catch", "return"}:
                var_nid = _make_id(stem, single_name)
                add_node(var_nid, single_name, line=_line_of(m.start(2)))
                add_edge(file_nid, var_nid, "defines")''',
    ),
    # 4b. Destructured variable nodes get a line number.
    (
        '''                    if name not in {"if", "for", "while", "switch", "catch", "return"}:
                        var_nid = _make_id(stem, name)
                        add_node(var_nid, name)
                        add_edge(file_nid, var_nid, "defines")''',
        '''                    if name not in {"if", "for", "while", "switch", "catch", "return"}:
                        var_nid = _make_id(stem, name)
                        add_node(var_nid, name, line=_line_of(m.start(3)))
                        add_edge(file_nid, var_nid, "defines")''',
    ),
    # 5. Method/function nodes get a line number.
    (
        '''        if re.match(r"^[A-Z]", name):
            continue
        nid = _make_id(stem, name)
        add_node(nid, name)
        add_edge(file_nid, nid, "defines")''',
        '''        if re.match(r"^[A-Z]", name):
            continue
        nid = _make_id(stem, name)
        add_node(nid, name, line=_line_of(m.start(1)))
        add_edge(file_nid, nid, "defines")''',
    ),
    # 6. New section 5b: multi-line signatures + nested local functions.
    (
        '''    # 6. Imports and Exports
    for m in re.finditer(r"""^\\s*import\\s+['"]([^'"]+)['"]""", src_clean, re.MULTILINE):''',
        '''    # 5b. ''' + MARKER + ''': declaration shapes the same-line pattern misses.
    _fn_keywords = {"if", "for", "while", "switch", "catch", "return", "await",
                    "throw", "yield", "assert", "new", "else", "do", "try",
                    "void", "dynamic", "final", "const", "var", "late",
                    "get", "set", "this", "super", "required"}

    # Multi-line signature: bare return-type line (ending in > or ?), then the
    # function name starting the next line, e.g.
    #   Future<(HandleChatMessageResult, ConversationMessage?, ContactModel?)>
    #   handleIncomingChatMessage({
    for m in re.finditer(r"^\\s{0,2}([a-z_]\\w*)\\s*\\(", src_clean, re.MULTILINE):
        name = m.group(1)
        if name in _fn_keywords:
            continue
        nid = _make_id(stem, name)
        if nid in defined:
            continue
        before = src_clean[: m.start()].rstrip("\\n")
        prev = before.rsplit("\\n", 1)[-1] if "\\n" in before else before
        if prev and "=" not in prev and re.fullmatch(r"\\s*[\\w<>,.?()\\[\\] ]*[>?]", prev):
            add_node(nid, name, line=_line_of(m.start(1)))
            add_edge(file_nid, nid, "defines")

    # Nested local functions (indent >= 3): an uppercase-led return type (or
    # void/dynamic) followed by a lowercase name and an opening paren, e.g. the
    # helpers declared inside a large use-case function body.
    for m in re.finditer(
        r"^\\s{3,}(?:static\\s+)?(?:[A-Z]\\w*(?:<[^;{}=\\n]+>)?\\??|void|dynamic)\\s+([a-z_]\\w*)\\s*\\(",
        src_clean,
        re.MULTILINE,
    ):
        name = m.group(1)
        if name in _fn_keywords:
            continue
        nid = _make_id(stem, name)
        if nid in defined:
            continue
        add_node(nid, name, line=_line_of(m.start(1)))
        add_edge(file_nid, nid, "defines", context="local_function")

    # 6. Imports and Exports
    for m in re.finditer(r"""^\\s*import\\s+['"]([^'"]+)['"]""", src_clean, re.MULTILINE):''',
    ),
]


# v2 artifact fixes, measured on the arch graph 2026-06-12:
#   - `T` god node (1,282 edges) from generic type parameters,
#   - nullable type refs split from their base type (`GroupRepository?` vs
#     `GroupRepository`),
#   - keyword/literal nodes (`return` 198 edges, `null`, `true`, `false`),
#   - multi-token getter shapes captured as types (`bool get` 138 edges).
EDITS_V2 = [
    # 0. Shared blacklist, inserted at module level.
    (
        '''def extract_dart(path: Path) -> dict:''',
        '''# MKNOON-PATCH dart-artifacts v2: labels that must never become graph
# nodes from Dart extraction — control keywords, literals, accessor words,
# and builtins (builtins re-checked after nullable-stripping).
_DART_ARTIFACT_LABELS = {
    "if", "for", "while", "switch", "catch", "return", "throw", "await",
    "yield", "new", "case", "else", "in", "is", "as", "get", "set",
    "null", "true", "false",
    "String", "int", "double", "bool", "num", "dynamic", "Object", "List",
    "Map", "Set", "void", "Future", "Stream",
}


def extract_dart(path: Path) -> dict:''',
    ),
    # 1. Variable-type reference nodes: merge nullable refs into the base
    # type, skip multi-token shapes and single-letter generic params.
    (
        '''                if var_type and var_type not in {"String", "int", "double", "bool", "num", "dynamic", "Object", "List", "Map", "Set", "void"}:
                    clean_type = var_type.split("<")[0].split(".")[-1].strip()
                    type_nid = _make_id(clean_type)
                    add_node(type_nid, clean_type, source_file=None)
                    add_edge(file_nid, type_nid, "references", context="variable_type")''',
        '''                if var_type and var_type not in {"String", "int", "double", "bool", "num", "dynamic", "Object", "List", "Map", "Set", "void"}:
                    clean_type = (
                        var_type.split("<")[0].split(".")[-1].strip().rstrip("?")
                    )
                    if (len(clean_type) > 1
                            and " " not in var_type
                            and clean_type not in _DART_ARTIFACT_LABELS):
                        type_nid = _make_id(clean_type)
                        add_node(type_nid, clean_type, source_file=None)
                        add_edge(file_nid, type_nid, "references", context="variable_type")''',
    ),
    # 2. Generic type lookups: same hygiene (this is the main `T` source).
    (
        '''        type_name = m.group(1).split(".")[-1].strip()
        clean_name = type_name.split("<")[0].strip()
        if clean_name not in type_blacklist:''',
        '''        type_name = m.group(1).split(".")[-1].strip()
        clean_name = type_name.split("<")[0].strip().rstrip("?")
        if (len(clean_name) > 1
                and clean_name not in type_blacklist
                and clean_name not in _DART_ARTIFACT_LABELS):''',
    ),
    # 3. Single-variable names: drop literals and single-letter generics.
    # (Anchors on the v1-patched text — applied after EDITS.)
    (
        '''            if single_name not in {"if", "for", "while", "switch", "catch", "return"}:
                var_nid = _make_id(stem, single_name)
                add_node(var_nid, single_name, line=_line_of(m.start(2)))
                add_edge(file_nid, var_nid, "defines")''',
        '''            if (single_name not in _DART_ARTIFACT_LABELS
                    and not (len(single_name) == 1 and single_name.isupper())):
                var_nid = _make_id(stem, single_name)
                add_node(var_nid, single_name, line=_line_of(m.start(2)))
                add_edge(file_nid, var_nid, "defines")''',
    ),
    # 4. Destructured names: same hygiene.
    (
        '''                    if name not in {"if", "for", "while", "switch", "catch", "return"}:
                        var_nid = _make_id(stem, name)
                        add_node(var_nid, name, line=_line_of(m.start(3)))
                        add_edge(file_nid, var_nid, "defines")''',
        '''                    if name not in _DART_ARTIFACT_LABELS:
                        var_nid = _make_id(stem, name)
                        add_node(var_nid, name, line=_line_of(m.start(3)))
                        add_edge(file_nid, var_nid, "defines")''',
    ),
]

# Go-side artifact fix: `t *testing.T` in every Go test file collapses to a
# bare `T` type-ref via rsplit('.') — 71 nodes / 1,282 edges of god-node noise
# in the arch graph. Single-letter type refs (incl. generic params) carry no
# query value; skip them in both branches.
EDITS_V2_GO = [
    (
        '''    if t == "type_identifier":
        text = _read_text(node, source)
        if text and text not in _GO_PREDECLARED_TYPES:
            out.append((text, "generic_arg" if generic else "type"))
        return
    if t == "qualified_type":
        text = _read_text(node, source).rsplit(".", 1)[-1]
        if text and text not in _GO_PREDECLARED_TYPES:
            out.append((text, "generic_arg" if generic else "type"))
        return''',
        '''    # ''' + MARKER_V2_GO + ''': single-letter type refs (generic params,
    # and `testing.T` collapsed by the rsplit below) are query noise.
    if t == "type_identifier":
        text = _read_text(node, source)
        if text and len(text) > 1 and text not in _GO_PREDECLARED_TYPES:
            out.append((text, "generic_arg" if generic else "type"))
        return
    if t == "qualified_type":
        text = _read_text(node, source).rsplit(".", 1)[-1]
        if text and len(text) > 1 and text not in _GO_PREDECLARED_TYPES:
            out.append((text, "generic_arg" if generic else "type"))
        return''',
    ),
]

# Newer 0.9.x extractors preserve qualified names such as `testing.T`, so only
# unqualified single-letter generic references still need filtering. Keep this
# as a separate exact-anchor variant: an unrecognized upstream shape must still
# fail closed instead of receiving a speculative patch.
EDITS_V2_GO_QUALIFIED = [
    (
        '''    if t == "type_identifier":
        text = _read_text(node, source)
        if text and text not in _GO_PREDECLARED_TYPES:
            out.append((text, "generic_arg" if generic else "type"))
        return
    if t == "qualified_type":
        # Keep the package qualifier so the generic stub rewire cannot attach
        # `testing.T` to an unrelated local type or function named T.
        text = _read_text(node, source)
        if text:
            out.append((text, "generic_arg" if generic else "type"))
        return''',
        '''    # ''' + MARKER_V2_GO + ''': single-letter unqualified type refs
    # (generic params) are query noise. Qualified refs retain their package.
    if t == "type_identifier":
        text = _read_text(node, source)
        if text and len(text) > 1 and text not in _GO_PREDECLARED_TYPES:
            out.append((text, "generic_arg" if generic else "type"))
        return
    if t == "qualified_type":
        # Keep the package qualifier so the generic stub rewire cannot attach
        # `testing.T` to an unrelated local type or function named T.
        text = _read_text(node, source)
        if text:
            out.append((text, "generic_arg" if generic else "type"))
        return''',
    ),
]

# 0.9.x detect() hardening skips symlinks whose target resolves outside the
# scan root — which empties the arch corpus (.graphify-arch-src/ is nothing but
# repo-owned symlinks pointing back into the repository). Opt-in override: when
# $GRAPHIFY_SYMLINK_SCOPE_ROOT is set (refresh_graph.py sets it to the repo
# root), targets under it are trusted too. Absent the env var, upstream's
# behavior is unchanged.
DETECT_MARKER = "MKNOON-PATCH symlink-scope v1"
DETECT_EDITS = [
    (
        '''def _resolves_under_root(path: Path, root: Path) -> bool:
    """True when ``path`` resolves to a target inside ``root``."""
    try:
        path.resolve().relative_to(root.resolve())
    except (OSError, RuntimeError, ValueError):
        return False
    return True''',
        '''def _resolves_under_root(path: Path, root: Path) -> bool:
    """True when ``path`` resolves to a target inside ``root``."""
    # ''' + DETECT_MARKER + ''': also trust symlink targets under
    # $GRAPHIFY_SYMLINK_SCOPE_ROOT (the repository root). The arch corpus is
    # repo-owned symlinks back into the repo; the outside-scan-root skip
    # (0.9.x hardening) would otherwise leave detect() with zero files.
    scope = os.environ.get("GRAPHIFY_SYMLINK_SCOPE_ROOT")
    if scope:
        try:
            path.resolve().relative_to(Path(scope).resolve())
            return True
        except (OSError, RuntimeError, ValueError):
            pass
    try:
        path.resolve().relative_to(root.resolve())
    except (OSError, RuntimeError, ValueError):
        return False
    return True''',
    ),
]

DEDUP_EDITS = [
    (
        '''                if score >= _MERGE_THRESHOLD:
                    # Identical labels across different source files almost always''',
        '''                if score >= _MERGE_THRESHOLD:
                    # ''' + DEDUP_MARKER + ''': merge only exact normalized-label
                    # matches, for every node type. Code identifiers are exact
                    # (…Retryable vs …Rejected are distinct symbols; upstream
                    # 0.9.x now also excludes code from both passes), and this
                    # repo's doc corpus uses systematic IDs (GK-011 vs GK-012
                    # session plans) that Jaro-Winkler scores as near-identical
                    # — different-label fuzzy merges would fuse unrelated plan
                    # docs into one community. (Note: the 2026-07-18 shrinking
                    # graph.json was NOT this — it was _semantic_id_remap
                    # migrating legacy doc-section ids; fixed by iterating
                    # build_from_json to a fixpoint once and re-persisting.)
                    if norm_label != neighbor_norm:
                        continue
                    # Identical labels across different source files almost always''',
    ),
]

# Newer upstream versions expanded the merge commentary and moved the old
# anchor, while still permitting differently named non-code nodes to fuzzy
# merge. Preserve the repo's exact-normalized-label policy at the new seam.
DEDUP_EDITS_CURRENT = [
    (
        '''                if score >= _MERGE_THRESHOLD:
                    # Belt-and-braces (#1046, narrowed by #2182): candidates are''',
        '''                if score >= _MERGE_THRESHOLD:
                    # ''' + DEDUP_MARKER + ''': this repo uses systematic IDs and
                    # template-shaped labels whose small differences are semantic.
                    # Only exact normalized labels may merge; differently named
                    # entities must remain distinct regardless of fuzzy score.
                    if norm_label != neighbor_norm:
                        continue
                    # Belt-and-braces (#1046, narrowed by #2182): candidates are''',
    ),
]


def patch_file(target: Path, marker: str, edits: list[tuple[str, str]]) -> bool:
    src = target.read_text(encoding="utf-8")
    if marker in src:
        print(f"already patched: {target}")
        return False

    backup = target.with_suffix(".py.orig")
    if not backup.exists():
        shutil.copy2(target, backup)
        print(f"backup: {backup}")

    for i, (old, new) in enumerate(edits, 1):
        count = src.count(old)
        if count != 1:
            sys.exit(
                f"{target.name} edit {i}: anchor matched {count} times (expected 1) "
                f"— upstream changed; re-derive the patch against {target}"
            )
        src = src.replace(old, new)

    target.write_text(src, encoding="utf-8")
    print(f"patched: {target} ({len(edits)} edits, marker '{marker}')")
    return True


def ensure_pristine(target: Path, markers: tuple[str, ...], final_marker: str) -> None:
    """Reset a partially-patched file to its pristine backup, and refresh a
    stale backup (left by a previous package version) when the file is clean."""
    src = target.read_text(encoding="utf-8")
    backup = target.with_suffix(".py.orig")
    if final_marker in src:
        return
    if any(mk in src for mk in markers):
        if not backup.exists():
            sys.exit(
                f"{target} is partially patched but {backup} is missing — "
                f"reinstall graphifyy, then re-run this script"
            )
        shutil.copy2(backup, target)
        print(f"restored pristine {target.name} from {backup}")
    else:
        # Unpatched: the current file IS pristine for this install. Overwrite
        # any backup a previous package version left behind so a later reset
        # can never resurrect old-version source.
        shutil.copy2(target, backup)


def main() -> None:
    dart_py = find_module_file("graphify.extractors.dart", "graphify.extract")
    go_py = find_module_file("graphify.extractors.go", "graphify.extract")
    dedup_py = find_module_file("graphify.dedup")

    if dart_py == go_py:
        # 0.8.x monolithic layout: one file carries Dart + Go extraction.
        targets = [
            (dart_py, MARKER_V2, EDITS + EDITS_V2 + EDITS_V2_GO,
             (MARKER, MARKER_V2, MARKER_V2_GO)),
        ]
    else:
        # 0.9.x split layout: per-language files under graphify/extractors/.
        go_src = go_py.read_text(encoding="utf-8")
        if MARKER_V2_GO in go_src or EDITS_V2_GO[0][0] in go_src:
            go_edits = EDITS_V2_GO
        elif EDITS_V2_GO_QUALIFIED[0][0] in go_src:
            go_edits = EDITS_V2_GO_QUALIFIED
        else:
            # Preserve patch_file's exact-anchor failure for unknown upstream
            # shapes rather than silently skipping a still-relevant safeguard.
            go_edits = EDITS_V2_GO
        targets = [
            (dart_py, MARKER_V2, EDITS + EDITS_V2, (MARKER, MARKER_V2)),
            (go_py, MARKER_V2_GO, go_edits, (MARKER_V2_GO,)),
        ]
    dedup_src = dedup_py.read_text(encoding="utf-8")
    if DEDUP_MARKER in dedup_src or DEDUP_EDITS[0][0] in dedup_src:
        dedup_edits = DEDUP_EDITS
    elif DEDUP_EDITS_CURRENT[0][0] in dedup_src:
        dedup_edits = DEDUP_EDITS_CURRENT
    else:
        dedup_edits = DEDUP_EDITS
    targets.append((dedup_py, DEDUP_MARKER, dedup_edits,
                    (DEDUP_MARKER_V1, DEDUP_MARKER)))

    detect_py = _resolve_module_file("graphify.detect")
    if detect_py is not None:
        detect_src = detect_py.read_text(encoding="utf-8")
        if DETECT_MARKER in detect_src or DETECT_EDITS[0][0] in detect_src:
            targets.append((detect_py, DETECT_MARKER, DETECT_EDITS, (DETECT_MARKER,)))
        else:
            print(
                f"note: {detect_py.name} has no symlink-scope anchor "
                f"(pre-0.9 detect?); skipping that patch"
            )

    changed_dirs: set[Path] = set()
    for target, final_marker, edits, markers in targets:
        ensure_pristine(target, markers, final_marker)
        if patch_file(target, final_marker, edits):
            changed_dirs.add(target.parent)
    # Clear stale bytecode only after an actual package-source edit. Routine
    # incremental refreshes should not churn the installed Python cache.
    for directory in changed_dirs:
        pycache = directory / "__pycache__"
        if pycache.exists():
            shutil.rmtree(pycache)
    print("extractor patch current; preserve AST caches for incremental refreshes")


if __name__ == "__main__":
    main()
