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
     symbol. The patch blocks fuzzy merges between two file_type=="code" nodes
     with differing normalized labels (natural-language/doc nodes untouched).

Idempotent: marker comments are written into the patched files; re-running is a
no-op. Re-apply after any `uv tool upgrade graphifyy` (the upgrade wipes it) —
refresh_arch_graph.sh runs this script automatically. After applying, clear the
AST cache (keyed by file hash only, NOT extractor version — stale results
survive otherwise):
    rm -rf graphify-out/cache/ast
then rebuild: ./graphify-arch/refresh_arch_graph.sh (arch) and re-extract the
full graph's Dart files.
"""

import re
import shutil
import subprocess
import sys
from pathlib import Path

MARKER = "MKNOON-PATCH dart-linenos v1"
MARKER_V2 = "MKNOON-PATCH dart-artifacts v2"
MARKER_V2_GO = "MKNOON-PATCH go-artifacts v2"
DEDUP_MARKER = "MKNOON-PATCH code-no-fuzzy v1"


def find_extract_py() -> Path:
    try:
        import graphify.extract as e  # type: ignore

        return Path(e.__file__)
    except ImportError:
        pass
    bin_path = shutil.which("graphify")
    if not bin_path:
        sys.exit("graphify CLI not found on PATH")
    shebang = Path(bin_path).read_text(errors="replace").splitlines()[0].lstrip("#!")
    out = subprocess.run(
        [shebang, "-c", "import graphify.extract as e; print(e.__file__)"],
        capture_output=True,
        text=True,
        check=True,
    )
    return Path(out.stdout.strip())


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

DEDUP_EDITS = [
    (
        '''                if score >= _MERGE_THRESHOLD:
                    # Identical labels across different source files almost always''',
        '''                if score >= _MERGE_THRESHOLD:
                    # ''' + DEDUP_MARKER + ''': code identifiers are exact — two
                    # differently-named declarations (e.g. ...Retryable vs
                    # ...Rejected, or a function vs its own file node) are
                    # distinct symbols, never spelling variants. Fuzzy merging
                    # is for natural-language/doc concept nodes only.
                    if (norm_label != neighbor_norm
                            and node.get("file_type") == "code"
                            and neighbor.get("file_type") == "code"):
                        continue
                    # Identical labels across different source files almost always''',
    ),
]


def patch_file(target: Path, marker: str, edits: list[tuple[str, str]]) -> None:
    src = target.read_text(encoding="utf-8")
    if marker in src:
        print(f"already patched: {target}")
        return

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


def main() -> None:
    extract_py = find_extract_py()
    src = extract_py.read_text(encoding="utf-8")
    backup = extract_py.with_suffix(".py.orig")
    if MARKER_V2 in src and MARKER_V2_GO in src:
        print(f"already patched (v2 + go-v2): {extract_py}")
    else:
        if MARKER in src:
            # Partially-patched install: reset to the pristine backup so the
            # full edit list can apply against known anchors.
            if not backup.exists():
                sys.exit(
                    f"{extract_py} is patched but {backup} is missing — "
                    f"reinstall graphifyy, then re-run this script"
                )
            shutil.copy2(backup, extract_py)
            print(f"restored pristine extract.py from {backup}")
        patch_file(extract_py, MARKER_V2, EDITS + EDITS_V2 + EDITS_V2_GO)
    patch_file(extract_py.parent / "dedup.py", DEDUP_MARKER, DEDUP_EDITS)
    # clear stale bytecode
    pycache = extract_py.parent / "__pycache__"
    if pycache.exists():
        shutil.rmtree(pycache)
    print("next: rm -rf graphify-out/cache/ast && rebuild both graphs")


if __name__ == "__main__":
    main()
