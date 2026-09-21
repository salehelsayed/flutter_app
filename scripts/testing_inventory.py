#!/usr/bin/env python3
"""Discover test files and existing runner plans without executing test bodies.

This is a generated inventory, not a second coverage manifest. A discovered
file or SIMS capability is not a test case and does not establish coverage.
Only the explicit --list-runners option starts the allowlisted listing commands.
"""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import fnmatch
import json
import os
from pathlib import Path, PurePosixPath
import re
import signal
import subprocess
import sys
import tempfile
import time


SCHEMA_VERSION = 1
SOURCE_EXTENSIONS = {".dart", ".go", ".py", ".sh", ".js", ".mjs", ".cjs", ".swift", ".kt", ".java", ".c", ".cc", ".cpp"}
SUPPORT_PARTS = {"fixture", "fixtures", "helper", "helpers", "support", "mocks", "fakes", "testdata"}
RUNNERS = (
    {"id": "host", "command": ["bash", "scripts/run_host_test_gates.sh", "host-all", "--list"],
     "required_paths": ["scripts/run_host_test_gates.sh"], "format": "numbered_plan"},
    {"id": "sims", "command": ["dart", "tool/sims/sims.dart", "full", "--list", "--format", "json"],
     "required_paths": ["tool/sims/sims.dart", ".dart_tool/package_config.json"], "format": "sims_json"},
    {"id": "sims_contracts", "command": ["bash", "scripts/run_test_gates.sh", "sims-contracts", "--list"],
     "required_paths": ["scripts/run_test_gates.sh"], "format": "numbered_plan"},
    {"id": "flutter_full_routes", "command": ["bash", "scripts/run_flutter_full_regression.sh", "--dry-run"],
     "required_paths": ["scripts/run_flutter_full_regression.sh"], "format": "full_routes", "temporary_output": True},
)


class InventoryError(ValueError):
    """The inventory could not be obtained completely or safely."""


def source_files(root: Path) -> list[str]:
    """Existing tracked and nonignored untracked files, sorted and deduplicated.

    Deleted paths intentionally remain the diff selector's responsibility.
    Submodule internals and ignored build outputs are not silently traversed.
    """
    result = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
    )
    if result.returncode:
        raise InventoryError("git ls-files failed; run inventory in a Git checkout")
    paths = result.stdout.decode("utf-8", errors="surrogateescape").split("\0")
    return sorted({path for path in paths if path and (root / path).is_file()})


def _ownership(parts: tuple[str, ...]) -> str:
    if "third_party" in parts or "vendor" in parts or "stub" in parts:
        return "vendor_or_stub"
    if parts[0] in {"Test-Flight-Improv", "archive", "archives", "artifacts"}:
        return "historical_or_project_evidence"
    return "project"


def _family(path: str) -> str | None:
    p = PurePosixPath(path)
    parts = p.parts
    name = p.name
    if name.endswith("_test.dart"):
        if "integration_test" in parts or "test_driver" in parts:
            return "flutter_device"
        return "flutter_host"
    if name.endswith("_test.go"):
        return "go"
    if p.suffix == ".py" and (name.startswith("test_") or name.endswith("_test.py")):
        return "python_unittest"
    if p.suffix == ".sh" and (name.endswith("_test.sh") or name.startswith("test_")):
        return "shell_contract"
    if p.suffix in {".js", ".mjs", ".cjs"} and (
        re.search(r"(?:[._-](?:test|spec)|^(?:test|spec)[_-])", p.stem)
        or any(part in {"test", "tests", "__tests__"} for part in parts[:-1])
    ):
        return "javascript_node"
    if p.suffix == ".swift" and re.search(r"Tests?$", p.stem):
        return "swift_xctest_ui" if any("UITests" in part for part in parts) else "swift_xctest"
    if p.suffix in {".kt", ".java"} and re.search(r"Tests?$", p.stem):
        return "android_instrumentation" if any("androidtest" in part.lower() for part in parts) else "kotlin_java_junit"
    if p.suffix in {".c", ".cc", ".cpp"} and re.search(r"(?:^test[_-]|[_-]test$)", p.stem):
        return "native_c_cpp"
    return None


def _support_role(path: str) -> str | None:
    p = PurePosixPath(path)
    parts = p.parts
    if p.suffix not in SOURCE_EXTENSIONS:
        return "fixture" if any(part in {"fixtures", "testdata"} for part in parts) else None
    in_test_tree = any(part in {"test", "tests", "integration_test", "test_driver"} or part.endswith("Tests") for part in parts)
    if not in_test_tree:
        return None
    if p.name.endswith((".g.dart", ".mocks.dart", ".freezed.dart")):
        return "generated"
    if any(part in {"fixtures", "fixture", "testdata"} for part in parts):
        return "fixture"
    if p.name.startswith("run_") and p.suffix == ".sh":
        return "runner_helper"
    return "helper"


def discover(root: Path) -> dict:
    """Return reproducible discovery metadata; no application/test imports."""
    root = Path(root).resolve()
    paths = source_files(root)
    modules = sorted({str(PurePosixPath(path).parent) for path in paths if PurePosixPath(path).name == "go.mod"})
    entries = []
    for path in paths:
        p = PurePosixPath(path)
        family = _family(path)
        role = "test_candidate" if family else _support_role(path)
        if not family and p.suffix in {'.dart', '.sh', '.py'} and (
                path.startswith('integration_test/')):
            if p.name.startswith(('run_', 'capture_')) or p.name.endswith('_harness.dart'):
                family, role = 'campaign', 'harness_candidate'
                if p.name.endswith('_harness.dart') and not re.search(r'\bmain\s*\(', (root/path).read_text()):
                    role = 'helper'
        if not role:
            continue
        # Generated and fixture files cannot become executable test evidence
        # merely by ending in a familiar test suffix.
        if any(part in {"fixtures", "fixture", "testdata"} for part in p.parts):
            role = "fixture"
        if p.name.endswith((".g.dart", ".mocks.dart", ".freezed.dart")):
            role = "generated"
        row = {"path": path, "family": family or "test_support", "role": role,
               "ownership": _ownership(p.parts), "status": "discovered",
               "actual_test_case_count": None, "runtime_seconds": None}
        if family == "go":
            matches = [module for module in modules if path.startswith(module + "/") or module == "."]
            row["module"] = max(matches, key=len) if matches else None
        entries.append(row)
    families = {}
    for name in sorted({row["family"] for row in entries}):
        rows = [row for row in entries if row["family"] == name]
        tests = [row for row in rows if row["role"] == "test_candidate"]
        families[name] = {
            "test_file_count": len(tests), "support_file_count": len(rows) - len(tests),
            "ownership_test_file_counts": dict(sorted(Counter(row["ownership"] for row in tests).items())),
            "suite_count": None, "actual_test_case_count": None,
            "runtime_seconds": None,
        }
    fingerprint = hashlib.sha256("\0".join(paths).encode("utf-8", errors="surrogateescape")).hexdigest()
    return {
        "schema_version": SCHEMA_VERSION,
        "source_file_count": len(paths), "source_paths_sha256": fingerprint,
        "test_file_count": sum(row["role"] == "test_candidate" for row in entries),
        "suite_count": None, "actual_test_case_count": None,
        "families": families, "entries": entries, "go_modules": modules,
        "runner_discovery": [dict(runner, status="NOT RUN") for runner in RUNNERS],
        "limitations": [
            "File discovery identifies candidates, not inspected assertions or verified feature coverage.",
            "Suite counts, dynamic/parameterized cases and runtimes remain unknown until authoritative listing/execution.",
            "SIMS capabilities and host planned commands are selectable groups, not actual test-case counts.",
            "Go -list runs package initialization/TestMain and does not enumerate dynamic subtests; it is not run automatically.",
            "Python imports, Node tests and native/Flutter compilation are not executed for static inventory.",
            "Ignored artifacts/build outputs and submodule interiors are excluded; vendor/stub and historical files are labeled separately.",
        ],
    }


def list_runner(root: Path, runner: dict, timeout_seconds: float = 60) -> dict:
    """Run only an existing safe listing, with a process-group timeout."""
    if runner.get("temporary_output"):
        # The older full runner creates empty log directories even in dry-run
        # mode. Keep those outside the checkout and clean them reliably.
        with tempfile.TemporaryDirectory(prefix="mknoon-inventory-") as output:
            concrete = dict(runner, temporary_output=False, command=[*runner["command"], "--output", output])
            result = list_runner(root, concrete, timeout_seconds)
            result["command"] = list(runner["command"])
            result.pop("temporary_output", None)
            return result
    row = dict(runner, status="BLOCKED", actual_test_case_count=None)
    missing = [path for path in runner["required_paths"] if not (root / path).is_file()]
    if missing:
        return dict(row, reason="Missing listing prerequisite", missing_paths=missing)
    started = time.monotonic()
    try:
        process = subprocess.Popen(runner["command"], cwd=root, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, start_new_session=True)
    except OSError as exc:
        return dict(row, reason=f"Listing executable unavailable: {exc.strerror}")
    try:
        stdout, stderr = process.communicate(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        stdout, stderr = process.communicate()
        return dict(row, reason="Listing timed out", duration_seconds=round(time.monotonic() - started, 3),
                    exit_status=process.returncode)
    row.update(duration_seconds=round(time.monotonic() - started, 3), exit_status=process.returncode)
    if process.returncode:
        return dict(row, status="FAIL", reason="Runner listing failed", stderr=stderr[-4000:])
    if runner["format"] == "classifications_tsv":
        records = [line.split('\t', 3) for line in stdout.splitlines() if line.strip()]
        if not records or any(len(record) != 4 for record in records):
            return dict(row, status="FAIL", reason="Invalid classification listing")
        row.update(plan_item_count=len(records), classifications=records)
    elif runner["format"] == "sims_json":
        try:
            plan = json.loads(stdout)
            rows = plan["rows"]
            if not isinstance(rows, list) or not rows or any(not isinstance(item, dict) or not item.get("id") for item in rows):
                raise ValueError("empty or invalid rows")
            ids = [item["id"] for item in rows]
            if len(set(ids)) != len(ids):
                raise ValueError("duplicate IDs")
        except (ValueError, KeyError, TypeError):
            return dict(row, status="FAIL", reason="Invalid or empty SIMS JSON listing")
        row.update(plan_item_count=len(rows), plan=plan)
    elif runner["format"] == "full_routes":
        labels = re.findall(r"^RUN \d+/\d+ (.+)$", stdout, flags=re.MULTILINE)
        routes = re.findall(r"^\s+route: (.+)$", stdout, flags=re.MULTILINE)
        if not labels or len(labels) != len(routes):
            return dict(row, status="FAIL", reason="Full dry-run returned zero or incomplete routes")
        row.update(plan_item_count=len(labels), planned_routes=[{"label": label, "command": command} for label, command in zip(labels, routes)])
    else:
        commands = re.findall(r"^\s*\d+[.)]\s+(.+)$", stdout, flags=re.MULTILINE)
        if not commands:
            return dict(row, status="FAIL", reason="Listing returned zero recognizable planned commands")
        row.update(plan_item_count=len(commands), planned_commands=commands)
    return dict(row, status="PASS")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Write generated JSON to an untracked artifact path; default stdout")
    parser.add_argument("--list-runners", action="store_true", help="Run bounded existing --list commands; never test bodies")
    args = parser.parse_args(argv)
    root = Path(__file__).resolve().parents[1]
    try:
        inventory = discover(root)
        if args.list_runners:
            inventory["runner_discovery"] = [list_runner(root, runner) for runner in RUNNERS]
        rules_path = root / 'tool/testing/selection.json'
        if rules_path.is_file():
            rules = json.loads(rules_path.read_text())
            if rules.get('full_inventory'):
                from mknoon_checks import make_full_plan
                settings = argparse.Namespace(base='HEAD', local=True, build_label='', flutter_workers=1, jobs=1, sims_jobs=1)
                plan, _ = make_full_plan(settings, root, rules, capture_toolchains=False)
                inventory.update({k:plan[k] for k in ('obligations','coverage_gaps','runner_expansions')})
        encoded = json.dumps(inventory, indent=2, sort_keys=True) + "\n"
        if args.output:
            target = args.output.resolve()
            try:
                relative = target.relative_to(root).as_posix()
            except ValueError:
                relative = None
            if relative:
                tracked = subprocess.run(["git", "ls-files", "--error-unmatch", "--", relative], cwd=root,
                                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
                if tracked.returncode == 0:
                    raise InventoryError("Refusing to overwrite a tracked file with generated inventory")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(encoded)
        else:
            print(encoded, end="")
        if args.list_runners and any(row["status"] != "PASS" for row in inventory["runner_discovery"]):
            return 2
        return 0
    except (InventoryError, OSError, subprocess.TimeoutExpired) as exc:
        print(f"Inventory error: {exc}", file=sys.stderr)
        return 2




def command_scope(command):
    """Return authoritative runner inputs/filters; unknown syntax owns no file.

    This deliberately does not interpret shell programs or trust parallel names
    metadata. New runner options need an explicit scope classification here.
    """
    if not command: return None
    executable = PurePosixPath(command[0]).name
    args = list(command[1:])
    if executable.startswith('python'):
        while args and args[0] in ('-B', '-u'): args.pop(0)
        if args[:2] != ['-m', 'unittest']: return None
        args = args[2:]
        flags, values, filters = {'-v','--verbose','-q','--quiet','-f','--failfast','-b','--buffer','-c','--catch'}, set(), {'-k'}
    elif executable in ('flutter', 'dart') and args[:1] == ['test']:
        args = args[1:]
        flags = {'--no-pub','--machine','--no-color','--no-test-assets','--coverage','--enable-asserts'}
        values = {'--concurrency','-j','--timeout','--reporter','-r','--file-reporter','--coverage-path'}
        filters = {'--name','-n','--plain-name','-N','--tags','-t','--exclude-tags','-x','--shard','--test-randomize-ordering-seed'}
    elif executable == 'node' and '--test' in args:
        flags, values = {'--test'}, {'--test-reporter','--test-reporter-destination','--test-concurrency','--test-timeout'}
        filters = {'--test-name-pattern','--test-skip-pattern','--test-shard','--test-only'}
    elif executable == 'go' and args[:1] == ['test']:
        args = args[1:]
        flags, values = {'-json','-v','-race','-cover','-failfast'}, {'-count','-timeout','-parallel','-cpu','-coverprofile','-covermode'}
        filters = {'-run','--run','-test.run','--test.run','-skip','-test.skip','-bench','-tags','-list','-short'}
    elif executable in ('bash', 'sh') and len(args) == 1 and args[0].endswith('_test.sh'):
        return dict(inputs=args, filters=[])
    elif executable.endswith('_test.sh') and not args:
        return dict(inputs=[command[0]], filters=[])
    else:
        return None
    inputs, selected = [], []
    i = 0
    while i < len(args):
        token = args[i]
        flag, equals, value = token.partition('=')
        if executable.startswith('python') and token.startswith('-k') and token != '-k':
            flag, equals, value = '-k', '=', token[2:]
        if flag in filters or flag in values:
            if flag in ('--test-only', '-short'):
                selected.append([flag, value or 'true']); i += 1; continue
            if not equals:
                i += 1
                if i >= len(args): return None
                value = args[i]
            if flag in filters: selected.append([flag, value])
        elif token in flags:
            pass
        elif token.startswith('-') or token in ('&&',';','|'):
            return None
        else:
            inputs.append(token)
        i += 1
    return dict(inputs=inputs, filters=selected)


def reconcile(root: Path, rules: dict, selected: list[dict], files: list[str], workers: int = 1) -> dict:
    """Expand manifest selectors against source and audited listing commands.

    No registered wrapper is taken as evidence that a whole family ran. Only
    explicit paths, parsed listing selectors and manifest mappings assign owners.
    This ledger describes obligations; execution outcomes are joined separately.
    """
    import shlex
    policy = rules['full_inventory']
    errors = validate_policy(root, rules, files)
    if errors: raise InventoryError('\n'.join(errors))
    inventory = discover(root)
    obligations = {}
    listings = []
    covered = {}
    covered_bindings = {}

    def receipt_binding(spec, **leaf):
        return {'owner':spec['owner'], **{k:spec[k] for k in ('capability','route') if k in spec}, **leaf}

    def cover(path, spec, **leaf):
        covered.setdefault(path, []).append(spec['owner'])
        value = receipt_binding(spec, **leaf)
        if value not in covered_bindings.setdefault(path, []): covered_bindings[path].append(value)

    def add(path, selector='', variant='', **values):
        identity = [path, selector, variant]
        oid = hashlib.sha256(json.dumps(identity, separators=(',', ':')).encode()).hexdigest()[:24]
        row = obligations.setdefault(oid, dict(id=oid, path=path, selector=selector, variant=variant,
                                               status='UNMAPPED', owners=[]))
        row.update(values)
        return row

    def paths_for(tokens, cwd='.', allow_filtered=False):
        found = set()
        scope = command_scope(tokens)
        if scope is None or (scope['filters'] and not allow_filtered): return found
        for token in scope['inputs']:
            token = str(PurePosixPath(cwd) / token.removeprefix('./'))
            if token in files and (_family(token) or token.endswith('_test.sh')):
                found.add(token)
            elif (root / token).is_dir() and not token.startswith(('-', '/')):
                found.update(p for p in files if p.startswith(token.rstrip('/') + '/') and p.endswith('_test.dart'))
        return found

    for check in selected:
        if check['kind'] in ('flutter', 'python', 'node', 'go'):
            actual_paths = paths_for(check['command'], check.get('cwd', '.'))
            for path in check.get('selected_paths', []):
                if path in actual_paths: cover(path, dict(owner=check['id']))
        scope = command_scope(check['command'])
        if scope and scope['filters']:
            for path in paths_for(check['command'], check.get('cwd', '.'), allow_filtered=True):
                add(path, json.dumps(scope['filters'], separators=(',', ':')), 'command-filter',
                    status='SELECTED', owners=[check['id']], family=_family(path),
                    reason='Exact command filter; does not own the remaining file cases')

    for spec in policy.get('listings', []):
        result = list_runner(root, spec, spec.get('timeout_seconds', 60))
        # Timing is execution-host evidence, not a portable candidate fingerprint.
        result.pop('duration_seconds', None)
        listings.append(result)
        if result['status'] != 'PASS':
            add(spec['id'], variant='listing', reason=result.get('reason', 'Listing unavailable'))
            continue
        if result.get('planned_routes'):
            check = next(c for c in selected if c['id'] == spec['owner'])
            check['expanded_routes'] = result['planned_routes']
            check['selected_paths'] = [r['label'] for r in result['planned_routes']]
        for command in result.get('planned_commands', []):
            tokens = shlex.split(command)
            # This audited listing describes the exact paths appended to one
            # unfiltered Flutter batch (run_host_test_gates.sh), not shell argv.
            if (spec['command'] == ['bash', 'scripts/run_host_test_gates.sh', 'host-all',
                                     '--dart-only', '--batch-flutter', '--list'] and
                    len(tokens) == 4 and tokens[:3] == ['Flutter', 'batch', 'path']):
                tokens = ['flutter', 'test', tokens[3]]
            for path in paths_for(tokens): cover(path, spec)
        for route in result.get('planned_routes', []):
            for path in paths_for(shlex.split(route['command'])): cover(path, spec, route=route['label'])
            add(spec['id'], route['label'], 'route', status='SELECTED', owners=[spec['owner']],
                command=route['command'], family='legacy_route', receipt_bindings=[receipt_binding(spec, route=route['label'])])

    for mapping in policy.get('mappings', []):
        owner = next(c for c in selected if c['id'] == mapping['owner'])
        if owner['kind'] in ('flutter', 'python', 'node', 'go'):
            scope = command_scope(owner['command'])
            if scope is None or scope['filters']: continue
        for path in files:
            if any(fnmatch.fnmatchcase(path, pattern) for pattern in mapping['patterns']):
                registration = mapping.get('source_registration')
                if registration and PurePosixPath(path).name + ' in Sources' not in (root/registration).read_text(): continue
                if mapping.get('untagged_only') and re.search(r'^//go:build ', (root/path).read_text(), re.M): continue
                cover(path, mapping)

    classifications = {}
    classification_spec = policy.get('classifications')
    if classification_spec:
        classification = list_runner(root, classification_spec)
        classification.pop('duration_seconds', None)
        listings.append(classification)
        if classification['status'] != 'PASS':
            add(classification_spec['id'], variant='listing', reason=classification.get('reason', 'Classification failed'))
        else:
            for category, kind, path, note in classification['classifications']:
                classifications.setdefault(path, []).append((category, kind, note))
            # The existing legacy command selects classified runner/test paths
            # in these four scopes, excluding only its declared typed owners.
            legacy = next((c for c in selected if c.get('capability')=='reliability.full.cleaned_legacy'), None)
            manifest = json.loads((root/'tool/sims/critical_features.json').read_text())
            capability = next((c for c in manifest['capabilities'] if c['id']=='reliability.full.cleaned_legacy'), None)
            if legacy and capability:
                command = capability['command']
                exclusions = {command[i+1] for i, value in enumerate(command[:-1]) if value=='--exclude-path'}
                from legacy_target_contracts import contracts
                audited = contracts(root)['reliability']
                legacy['expanded_legacy_routes'] = [{'label': label} for label in audited]
                for label, contract in audited.items():
                    add('reliability_routes', label, 'route', status='SELECTED', owners=[legacy['id']],
                        family='legacy_route', receipt_bindings=[dict(owner=legacy['id'], route=label)])
                for path, records in classifications.items():
                    if path not in exclusions and any(c in ('1to1','group','intro','move-feature') and k in ('runner','test') for c,k,_ in records):
                        for label, contract in audited.items():
                            if path in contract['owns']:
                                cover(path, dict(owner=legacy['id'], route=label))

    automatic = {}
    for entry in inventory['entries']:
        path, family = entry['path'], entry['family']
        row = add(path, family=family, role=entry['role'], ownership=entry['ownership'])
        if entry['ownership'] != 'project' or entry['role'] not in ('test_candidate', 'harness_candidate'):
            row.update(status='EXCLUDED', reason=entry['ownership'] if entry['ownership'] != 'project' else entry['role'])
            continue
        exclusions = [e for e in policy.get('exclusions', []) if fnmatch.fnmatchcase(path, e['pattern'])]
        if exclusions:
            row.update(status=exclusions[0].get('status','EXCLUDED'), reason=exclusions[0]['reason']); continue
        records = classifications.get(path, [])
        if entry['role'] == 'harness_candidate' and records and all(c == 'support' for c,_,_ in records):
            row.update(status='EXCLUDED', reason='; '.join(sorted({n for _,_,n in records})))
            continue
        owners = sorted(set(covered.get(path, [])))
        if owners:
            row.update(status='SELECTED', owners=owners, receipt_bindings=covered_bindings.get(path, [])); continue
        supported = any(a['family'] == family and any(fnmatch.fnmatchcase(path, p) for p in a['patterns'])
                        for a in policy.get('automatic', []))
        if not supported:
            row['reason'] = ('; '.join(sorted({n for _,_,n in records})) + '; no exact full execution mapping') if records else 'No exact executable selection for ' + family + ': ' + path
            continue
        cwd = '.'
        variant = ''
        if family == 'flutter_host':
            parents = [p for p in files if p.endswith('/pubspec.yaml') and path.startswith(p[:-12])]
            if parents: cwd = str(PurePosixPath(max(parents, key=len)).parent)
        if family == 'go':
            cwd = entry.get('module')
            if not cwd:
                row['reason'] = 'Go source has no module'; continue
            tag = re.search(r'^//go:build (.+)$', (root/path).read_text(), re.M)
            if tag:
                variant = tag[1]
                if not re.fullmatch('[A-Za-z0-9_]+', variant):
                    row['reason'] = 'Go build expression needs explicit platform/tag mapping: ' + variant; continue
        key = (family, cwd, variant)
        automatic.setdefault(key, []).append(path)

    for (family, cwd, variant), paths in sorted(automatic.items()):
        cid = 'full.auto.' + family + '.' + hashlib.sha256((cwd + ':' + variant).encode()).hexdigest()[:10]
        relative = [str(PurePosixPath(p).relative_to(cwd)) if cwd != '.' else p for p in sorted(paths)]
        row = dict(id=cid, kind={'flutter_host':'flutter', 'python_unittest':'python',
                   'javascript_node':'node', 'go':'go'}[family], paths=relative,
                   selected_paths=sorted(paths), cwd=cwd, timeout_seconds=7200,
                   boundary='Discovered ' + family + ' source tests', resources=['unknown'])
        if family == 'flutter_host':
            row['command'] = ['flutter', 'test', '--no-pub', '--machine', f'--concurrency={workers}', '--timeout=2m', *relative]
            row['requirements'] = ['flutter']
        elif family == 'python_unittest':
            # Isolate files: equal module basenames across test trees are common.
            for path in paths:
                file_id = cid + '.' + hashlib.sha256(path.encode()).hexdigest()[:10]
                file_row = dict(row, id=file_id, paths=[path], selected_paths=[path],
                                command=[sys.executable, '-m', 'unittest', '-v', path])
                selected.append(file_row)
                add(path, status='SELECTED', owners=[file_id])
            continue
        elif family == 'javascript_node':
            row['command'] = ['node', '--test', '--test-reporter=tap', *relative]
            row['requirements'] = ['node']
        else:
            packages = sorted({'./' + str(PurePosixPath(p).parent) for p in relative})
            row['packages'] = packages
            row['command'] = ['go', 'test', '-json', '-count=1', '-timeout=20m', *(['-tags='+variant] if variant else []), *packages]
            row['requirements'] = ['go']
        selected.append(row)
        for path in paths: add(path, status='SELECTED', owners=[cid])

    for catalog in policy.get('catalogs', []):
        text = (root / catalog['path']).read_text()
        if catalog.get('start'): text = text.split(catalog['start'], 1)[1]
        if catalog.get('end'): text = text.split(catalog['end'], 1)[0]
        selectors = sorted(set(re.findall(catalog['pattern'], text)))
        if catalog.get('resolve_constants'):
            constants = dict(re.findall(r"const String (\w+) =\s*'([^']+)'", (root/catalog['path']).read_text()))
            selectors = sorted({token.strip("'") if token.startswith("'") else constants[token] for token in selectors})
        selectors = [s for s in selectors if s not in catalog.get('exclude_selectors', [])]
        if not selectors:
            add(catalog['path'], variant=catalog.get('variant',''), reason='Scenario expansion returned zero selectors')
        bindings = {}
        for binding in catalog.get('bindings', []):
            for selector in binding.get('selectors', []):
                bindings.setdefault(selector, []).append({k:binding[k] for k in ('owner','capability','route') if k in binding})
            if 'path' not in binding: continue
            source = (root / binding['path']).read_text()
            if binding.get('start'): source = source.split(binding['start'], 1)[1]
            if binding.get('end'): source = source.split(binding['end'], 1)[0]
            for selector in re.findall(binding['pattern'], source):
                bindings.setdefault(selector, []).append({k:binding[k] for k in ('owner','capability','route') if k in binding})
        for selector in selectors:
            owners = sorted({b['owner'] for b in bindings.get(selector, [])})
            add(catalog['path'], selector, catalog.get('variant', ''), family='scenario',
                reason=catalog['reason'] if not owners else 'Exact adapter scenario selection',
                owners=owners, receipt_bindings=bindings.get(selector, []), status='SELECTED' if owners else 'UNMAPPED',
                command=[arg.replace('{selector}', selector) for arg in catalog.get('command_template', [])])

    for item in policy.get('obligations', []):
        add(item['path'],item.get('selector',''),item.get('variant',''),status='SELECTED',owners=[item['owner']],family='exact_variant',owner_capability=item.get('owner_capability'),receipt_bindings=[receipt_binding(item)],reason=item.get('reason','Exact source-owned variant'))

    for alias in policy.get('gate_aliases', []):
        source=(root/alias['path']).read_text()
        for array in alias['arrays']:
            block=source.split(array+'=(',1)[1].split('\n)',1)[0]
            for path in sorted(set(re.findall(r'"(test/[^"\n]+_test\.dart)"',block))):
                add(path,'gate:'+array,'flutter-host-default',status='SELECTED',owners=[alias['owner']],
                    family='result_alias',owner_capability=alias['owner_capability'],receipt_bindings=[receipt_binding(alias, capability=alias['owner_capability'])],
                    reason='Exact gate host path executes in the canonical complete host batch; integration and Go gate variants remain selected.')

    sims_path = root / 'tool/sims/critical_features.json'
    if sims_path.exists():
        manifest = json.loads(sims_path.read_text())
        byid = {c['id']: c for c in manifest['capabilities']}
        for check in selected:
            if check['kind'] != 'sims': continue
            rows = [c for c in byid.values() if c.get('active', True) and check.get('sims_mode','major') in c.get('modes', [])]
            if check.get('capability') != '*':
                wanted = {check.get('capability')}
                while True:
                    deps = {d for i in wanted for d in byid[i].get('dependencies', [])}
                    if deps <= wanted: break
                    wanted |= deps
                rows = [c for c in rows if c['id'] in wanted]
            check['selected_paths'] = sorted(c['id'] for c in rows)
            check['expanded_capabilities'] = rows
            for c in rows:
                add('tool/sims/critical_features.json', c['id'], c.get('buildProfile',''),
                    status='SELECTED', owners=[check['id']], family='sims', command=c['command'],
                    receipt_bindings=[dict(owner=check['id'], capability=c['id'])])
        selected_capabilities = {o['selector'] for o in obligations.values() if o.get('family') == 'sims'}
        for c in byid.values():
            if c.get('active', True) and set(c.get('modes', [])) & {'major','full'} and c['id'] not in selected_capabilities:
                add('tool/sims/critical_features.json', c['id'], c.get('buildProfile',''),
                    family='sims', reason='Active major/full capability has no selected full command', command=c['command'])
            if not c.get('active', True):
                add('tool/sims/critical_features.json', c['id'], c.get('buildProfile',''),
                    status='INACTIVE', reason=c.get('inactiveReason', 'Manifest marks capability inactive'), family='sims')

    for cid, check in rules.get('checks', {}).items():
        if check['kind'] == 'manual':
            add('tool/testing/selection.json', cid, 'signed-candidate', status='MANUAL',
                family='manual', reason=check['boundary'], assertions=check.get('assertions', []))

    return dict(obligations=sorted(obligations.values(), key=lambda r:(r['path'],r['selector'],r['variant'])),
                coverage_gaps=[r['id'] for r in obligations.values() if r['status'] in ('UNMAPPED', 'MANUAL')],
                runner_expansions=listings)


def validate_policy(root, rules, files):
    policy = rules.get('full_inventory')
    if policy is None: return []
    errors = []
    owners = {c['id'] for c in rules.get('full_commands', [])}
    commands = {c['id']: c for c in rules.get('full_commands', [])}
    receipt_specs = policy.get('mappings', []) + policy.get('listings', []) + [
        binding for catalog in policy.get('catalogs', []) for binding in catalog.get('bindings', [])] + policy.get('obligations', []) + policy.get('gate_aliases', [])
    for spec in receipt_specs:
        owner = commands.get(spec.get('owner'), {})
        if owner.get('kind') == 'sims' and not spec.get('capability'):
            errors.append('Composite SIMS ownership requires an exact capability: ' + spec['owner'])
        if owner.get('kind') == 'legacy' and spec.get('format') != 'full_routes' and not spec.get('route'):
            errors.append('Composite legacy ownership requires an exact route: ' + spec['owner'])
        if any(k in spec and (not isinstance(spec[k], str) or not spec[k]) for k in ('capability', 'route')):
            errors.append('Invalid child receipt identity')
    families = {'flutter_host', 'python_unittest', 'javascript_node', 'go'}
    for item in policy.get('automatic', []):
        if item.get('family') not in families or not item.get('patterns'):
            errors.append('Invalid automatic full inventory family')
    for item in policy.get('exclusions', []):
        if item.get('source_sha256'):
            source=root/item.get('pattern','')
            if not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest() != item['source_sha256']:
                errors.append('Support/manual source changed; classification requires review: '+item.get('pattern',''))
        if not item.get('reason') or not any(fnmatch.fnmatchcase(p, item.get('pattern','')) for p in files):
            errors.append('Stale or unexplained inventory exclusion: ' + item.get('pattern',''))
    for item in policy.get('mappings', []) + policy.get('listings', []):
        if item.get('owner') not in owners: errors.append('Unknown full inventory owner: ' + item.get('owner',''))
        if 'patterns' in item and (not item.get('reason') or not all(
                any(fnmatch.fnmatchcase(p, pattern) for p in files) for pattern in item['patterns'])):
            errors.append('Stale or unexplained full inventory mapping')
    for item in policy.get('obligations', []):
        if item.get('owner') not in owners or not (root/item.get('path','')).is_file():
            errors.append('Invalid exact obligation owner/path')
    safe_listings = [r['command'] for r in RUNNERS] + [
        ['bash','scripts/run_host_test_gates.sh','host-all','--dart-only','--batch-flutter','--list'],
        ['bash','scripts/run_host_test_gates.sh','performance-host','--list']]
    for item in policy.get('listings', []):
        command = list(item.get('command', []))
        if command[:3] == ['bash','scripts/run_flutter_full_regression.sh','--dry-run']:
            rest = command[3:]
            if len(rest)%2 == 0 and all(rest[i]=='--exclude-label' for i in range(0,len(rest),2)):
                command = command[:3]
        if command not in safe_listings:
            errors.append('Full inventory listing must use an audited listing command: ' + item.get('id',''))
    classification = policy.get('classifications')
    if classification and classification.get('command') != ['bash','scripts/check_reliability_simulation_discovery.sh','--classifications-tsv']:
        errors.append('Invalid static classification command')
    for item in policy.get('catalogs', []):
        try:
            source = (root / item['path']).read_text()
            if item.get('start'): source = source.split(item['start'],1)[1]
            if item.get('end'): source = source.split(item['end'],1)[0]
            if not item.get('reason') or not re.findall(item['pattern'], source):
                errors.append('Empty or unexplained scenario catalog: ' + item['path'])
            for binding in item.get('bindings', []):
                if binding.get('owner') not in owners or ('path' in binding and not (root/binding['path']).is_file()) or not (binding.get('selectors') or binding.get('pattern')):
                    errors.append('Invalid scenario owner binding: ' + item['path'])
        except (KeyError, IndexError, OSError, re.error):
            errors.append('Invalid scenario extraction: ' + item.get('path',''))
    return errors


if __name__ == "__main__":
    raise SystemExit(main())
