#!/usr/bin/python3
"""Read-only report on host build jobs that may still use this checkout.

Takes no arguments. Runs only three fixed query forms (ps, lsof cwd, lsof open
files) with shell=False and prints one sanitized JSON object. It never stops,
changes or writes anything outside its own query children, and it reports
uncertainty instead of guessing. The only process it ever ends is its own query
child when that query overruns its time or output bound.

Bounds: QUERY_TIMEOUT_S per query (never more than the remaining
TOTAL_BUDGET_S), MAX_OUTPUT_BYTES collected per query (stderr is discarded),
MAX_CWD_QUERIES candidates, MAX_FD_QUERIES related processes,
MAX_ANCESTRY_DEPTH ancestors and MAX_BUILD_FDS reported files per process.
"""

import json
import os
import posixpath
import re
import selectors
import subprocess
import sys
import time

REPO_ROOT = "/Volumes/CrucialX9/flutter_app"
BUILD_ROOTS = (("build/app", REPO_ROOT + "/build/app"), ("build/ios", REPO_ROOT + "/build/ios"))

PS_VECTOR = ["/bin/ps", "-axo", "pid=,ppid=,lstart=,etime=,stat=,comm="]
QUERY_ENV = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"}
QUERY_TIMEOUT_S = 10
MAX_OUTPUT_BYTES = 4 * 1024 * 1024
MAX_CWD_QUERIES = 48
MAX_FD_QUERIES = 40
MAX_ANCESTRY_DEPTH = 6
MAX_BUILD_FDS = 20
TOTAL_BUDGET_S = 90
READ_CHUNK = 65536

BUILD_FAMILY_NAMES = {"bash", "sh", "dart", "dartaotruntime", "flutter"}
STORE_JOB_NAMES = {"bash", "sh"}
IOS_JOB_NAMES = {"dart", "dartaotruntime", "flutter"}

JOB_HINTS = {
    "store_release_build": {
        "container_client_command": "bash docker-ws/build_store_release.sh",
        "container_client_start": "2026-10-14 14:47:54 (container clock)",
        "root_names": sorted(STORE_JOB_NAMES),
    },
    "ios_profile_build": {
        "container_client_command": "flutter build ios --profile (release defines file)",
        "container_client_start": "2026-10-14 23:11:04 (container clock)",
        "root_names": sorted(IOS_JOB_NAMES),
    },
}

PS_LINE = re.compile(
    r"^\s*(\d+)\s+(\d+)\s+([A-Z][a-z]{2} [A-Z][a-z]{2}\s+\d{1,2} \d{2}:\d{2}:\d{2} \d{4})"
    r"\s+(\S+)\s+(\S+)\s+(\S.*?)\s*$"
)
ETIME = re.compile(r"^(\d{1,5}-)?(\d{1,2}:)?\d{1,2}:\d{2}$")
STAT = re.compile(r"^[A-Za-z<>+]{1,8}$")
SAFE_NAME = re.compile(r"^[A-Za-z0-9._+-]{1,40}$")
SAFE_COMPONENT = re.compile(r"^[A-Za-z0-9._+@=,-]{1,80}$")
LSOF_TAGS = set("pftan")


class QueryLimit(Exception):
    pass


def _positive_pid(pid):
    if isinstance(pid, bool) or not isinstance(pid, int) or pid <= 0:
        raise ValueError("pid must be a positive int")
    return str(pid)


def cwd_vector(pid):
    return ["/usr/sbin/lsof", "-nP", "-a", "-p", _positive_pid(pid), "-d", "cwd", "-Fn"]


def fd_vector(pid):
    return ["/usr/sbin/lsof", "-nP", "-a", "-p", _positive_pid(pid), "-F", "pftan"]


def classify_vector(vector):
    vector = list(vector)
    if vector == PS_VECTOR:
        return "ps"
    if len(vector) in (7, 8) and vector[4].isdigit() and int(vector[4]) > 0:
        pid = int(vector[4])
        if vector == cwd_vector(pid):
            return "cwd"
        if vector == fd_vector(pid):
            return "fds"
    return None


def run_query(vector, timeout):
    """Runs one fixed vector, collecting at most MAX_OUTPUT_BYTES of stdout before the deadline."""
    if classify_vector(vector) is None:
        raise ValueError("query vector is not one of the fixed forms")
    deadline = time.monotonic() + max(0.0, min(timeout, QUERY_TIMEOUT_S))
    child = subprocess.Popen(
        list(vector),
        shell=False,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        env=dict(QUERY_ENV),
        close_fds=True,
    )
    chunks, size, failure = [], 0, None
    selector = selectors.DefaultSelector()
    try:
        selector.register(child.stdout, selectors.EVENT_READ)
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                failure = "timeout"
                break
            if not selector.select(remaining):
                continue
            data = os.read(child.stdout.fileno(), READ_CHUNK)
            if not data:
                break
            size += len(data)
            if size > MAX_OUTPUT_BYTES:
                failure = "output_limit"
                break
            chunks.append(data)
    finally:
        selector.close()
        if failure is not None and child.poll() is None:
            child.kill()
        child.stdout.close()
        try:
            code = child.wait(timeout=max(0.1, deadline - time.monotonic()) if failure is None else 5)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait(timeout=5)
            failure = failure or "timeout"
    if failure is not None:
        raise QueryLimit(failure)
    return code, b"".join(chunks)


def _safe_name(comm):
    name = posixpath.basename(comm.rstrip("/"))
    return name if SAFE_NAME.match(name) else "other"


def parse_ps(data):
    rows = {}
    for line in data.decode("utf-8", "replace").splitlines():
        if not line.strip():
            continue
        match = PS_LINE.match(line)
        if not match:
            return None
        pid, ppid, lstart, etime, stat, comm = match.groups()
        if not ETIME.match(etime) or not STAT.match(stat) or int(pid) in rows:
            return None
        rows[int(pid)] = {
            "pid": int(pid),
            "ppid": int(ppid),
            "lstart": re.sub(r"\s+", " ", lstart),
            "etime": etime,
            "stat": stat,
            "name": _safe_name(comm),
        }
    return rows or None


def parse_lsof(data, pid):
    """Returns the per-descriptor records for exactly `pid`, or None if the output is not a clean -F record set."""
    lines = [line for line in data.decode("utf-8", "replace").splitlines() if line]
    if not lines or lines[0] != "p" + str(pid):
        return None
    fds, current = [], None
    for line in lines[1:]:
        tag, value = line[0], line[1:]
        if tag not in LSOF_TAGS or tag == "p":
            return None
        if tag == "f":
            if not value:
                return None
            current = {"fd": value}
            fds.append(current)
        elif current is None or tag in current:
            return None
        else:
            current[tag] = value
    return fds


def parse_cwd(data, pid):
    fds = parse_lsof(data, pid)
    if fds is None or len(fds) != 1 or fds[0].get("fd") != "cwd" or not fds[0].get("n", "").startswith("/"):
        return "malformed"
    path = posixpath.normpath(fds[0]["n"])
    if path == REPO_ROOT:
        return "repo_root"
    if path.startswith(REPO_ROOT + "/"):
        return "repo_subdir"
    return "other"


def _under(path, root):
    if not path.startswith("/"):
        return None
    parts = posixpath.normpath(path).split("/")
    root_parts = root.split("/")
    if len(parts) > len(root_parts) and parts[: len(root_parts)] == root_parts:
        rel = parts[len(root_parts):]
        return "/".join(rel) if all(SAFE_COMPONENT.match(p) for p in rel) else "<omitted-unsafe-name>"
    return None


def parse_build_fds(data, pid):
    fds = parse_lsof(data, pid)
    if fds is None:
        return None
    found = []
    for fd in fds:
        name = fd.get("n")
        if not name:
            continue
        for label, root in BUILD_ROOTS:
            rel = _under(name, root)
            if rel is not None:
                access = fd.get("a") if fd.get("a") in ("r", "w", "u") else "unknown"
                found.append({"root": label, "access": access, "relpath": rel})
                break
    return found


def _ancestry(rows, pid):
    names, seen, current = [], {pid}, rows[pid]["ppid"]
    while current in rows and current not in seen:
        if len(names) == MAX_ANCESTRY_DEPTH:
            return names, True
        seen.add(current)
        names.append(rows[current]["name"])
        current = rows[current]["ppid"]
    return names, False


def _parent_kind(rows, row):
    if row["ppid"] == 1:
        return "launchd"
    parent = rows.get(row["ppid"])
    if parent is None:
        return "missing"
    return "python" if parent["name"].lower().startswith("python") else "other"


def _descendants(rows, roots, limit):
    children = {}
    for row in rows.values():
        children.setdefault(row["ppid"], []).append(row["pid"])
    found, frontier = [], sorted(roots)
    while frontier:
        pid = frontier.pop(0)
        for child in sorted(children.get(pid, [])):
            if child in roots or child in found:
                continue
            if len(found) == limit:
                return found, True
            found.append(child)
            frontier.append(child)
    return found, False


def _query(runner, vector, deadline, reasons, failure_reason):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        reasons.add("budget_exceeded")
        return None
    try:
        code, data = runner(vector, min(QUERY_TIMEOUT_S, remaining))
    except Exception:
        reasons.add(failure_reason)
        return None
    if code != 0 or data is None or len(data) > MAX_OUTPUT_BYTES:
        reasons.add(failure_reason)
        return None
    return data


def _result(status, reasons, processes, jobs, coverage):
    return {
        "schema": "mknoon.host-build-jobs-diagnostic.v2",
        "status": status,
        "reasons": sorted(reasons),
        "repo_root_checked": "flutter_app checkout root (exact match only)",
        "time_basis": "lstart is Mac local time text with no UTC offset; job hints use the container clock",
        "coverage": coverage,
        "limits": {
            "scope": "bounded observation of build-family processes by name and repo-root cwd; "
                     "not a host-idle certificate; command lines are never read, so a match is not proof of "
                     "identity; an absent open write handle is not proof a process cannot write later; "
                     "says nothing about cooperative lease ownership",
            "max_cwd_queries": MAX_CWD_QUERIES,
            "max_fd_queries": MAX_FD_QUERIES,
            "query_timeout_s": QUERY_TIMEOUT_S,
            "total_budget_s": TOTAL_BUDGET_S,
        },
        "observed_processes": processes,
        "jobs": jobs,
    }


def _unknown_jobs(note):
    return {key: dict(hint, attribution="UNKNOWN", candidate_pids=[], note=note) for key, hint in JOB_HINTS.items()}


def diagnose(runner):
    deadline = time.monotonic() + TOTAL_BUDGET_S
    reasons = set()
    coverage = {
        "positive_control": "none: no approved query proves which process is the bridge server",
        "family_candidates": 0,
        "cwd_queried": 0,
        "cwd_unresolved": 0,
        "fd_targets": 0,
        "complete": False,
    }

    first = _query(runner, PS_VECTOR, deadline, reasons, "ps_failed")
    if first is None:
        return _result("INCONCLUSIVE", reasons, [], _unknown_jobs("ps unavailable"), coverage)
    rows = parse_ps(first)
    if rows is None:
        reasons.add("ps_unparseable")
        return _result("INCONCLUSIVE", reasons, [], _unknown_jobs("ps unparseable"), coverage)

    family = sorted(pid for pid, row in rows.items() if row["name"] in BUILD_FAMILY_NAMES)
    coverage["family_candidates"] = len(family)
    if len(family) > MAX_CWD_QUERIES:
        reasons.add("candidate_limit_exceeded")
        family = family[:MAX_CWD_QUERIES]

    cwd_class = {}
    for pid in family:
        data = _query(runner, cwd_vector(pid), deadline, reasons, "cwd_query_failed")
        if data is None:
            cwd_class[pid] = "unknown"
            continue
        cwd_class[pid] = parse_cwd(data, pid)
        if cwd_class[pid] == "malformed":
            reasons.add("lsof_unparseable")
    coverage["cwd_queried"] = len(family)
    coverage["cwd_unresolved"] = sum(1 for c in cwd_class.values() if c in ("unknown", "malformed"))
    if any(c == "repo_subdir" for c in cwd_class.values()):
        reasons.add("out_of_scope_repo_cwd")

    in_repo = [pid for pid in family if cwd_class[pid] in ("repo_root", "repo_subdir")]
    repo_roots = [pid for pid in family if cwd_class[pid] == "repo_root"]
    related, related_truncated = _descendants(rows, set(in_repo), MAX_FD_QUERIES)
    if related_truncated:
        reasons.add("descendant_limit_exceeded")
    fd_targets = (in_repo + related)[:MAX_FD_QUERIES]
    if len(in_repo) + len(related) > MAX_FD_QUERIES:
        reasons.add("descendant_limit_exceeded")
    coverage["fd_targets"] = len(fd_targets)

    shown = [pid for pid in family if cwd_class[pid] != "other"] + related
    processes = {}
    for pid in shown:
        row = rows[pid]
        ancestry, ancestry_truncated = _ancestry(rows, pid)
        processes[pid] = {
            "pid": pid,
            "ppid": row["ppid"],
            "parent_kind": _parent_kind(rows, row),
            "name": row["name"],
            "lstart_local_text": row["lstart"],
            "etime": row["etime"],
            "stat": row["stat"],
            "cwd_class": cwd_class.get(pid, "not_queried"),
            "ancestry": ancestry,
            "ancestry_truncated": ancestry_truncated,
            "build_fds": [],
            "build_fds_truncated": False,
            "fd_query": "not_run",
            "revalidated": None,
        }

    for pid in fd_targets:
        data = _query(runner, fd_vector(pid), deadline, reasons, "fd_query_failed")
        if data is None:
            processes[pid]["fd_query"] = "failed"
            continue
        fds = parse_build_fds(data, pid)
        if fds is None:
            processes[pid]["fd_query"] = "malformed"
            reasons.add("lsof_unparseable")
            continue
        processes[pid]["fd_query"] = "ok"
        processes[pid]["build_fds"] = fds[:MAX_BUILD_FDS]
        if len(fds) > MAX_BUILD_FDS:
            processes[pid]["build_fds_truncated"] = True
            reasons.add("build_fd_list_truncated")

    second = _query(runner, PS_VECTOR, deadline, reasons, "revalidation_failed")
    later = parse_ps(second) if second is not None else None
    if later is None:
        reasons.add("revalidation_failed")
    for pid in list(processes) + [p for p in family if p not in processes]:
        before = rows[pid]
        after = later.get(pid) if later else None
        same = after is not None and all(after[k] == before[k] for k in ("ppid", "lstart", "name"))
        if pid in processes:
            processes[pid]["revalidated"] = bool(same)
        if not same:
            reasons.add("process_changed_during_queries")

    jobs = {}
    for key, hint in JOB_HINTS.items():
        names = set(hint["root_names"])
        candidates = [pid for pid in repo_roots if rows[pid]["name"] in names]
        if len(candidates) == 1:
            attribution = "UNIQUE_CANDIDATE"
            note = "one process with this name and repo-root cwd; command line not read, so not proof of identity"
        elif candidates:
            attribution, note = "AMBIGUOUS", "several processes with this name and repo-root cwd"
            reasons.add("ambiguous_attribution")
        else:
            attribution = "NONE_OBSERVED"
            note = "no process with this name and repo-root cwd was seen; not proof the job finished or outputs are free"
        if attribution != "UNIQUE_CANDIDATE":
            reasons.add("job_not_positively_resolved")
        jobs[key] = dict(hint, attribution=attribution, candidate_pids=candidates, note=note)

    reasons.add("no_positive_control")
    coverage["complete"] = not (reasons - {"no_positive_control"})
    return _result("INCONCLUSIVE", reasons, [processes[p] for p in sorted(processes)], jobs, coverage)


def main(argv, write=sys.stdout.write):
    if argv:
        write(json.dumps({"schema": "mknoon.host-build-jobs-diagnostic.v2", "status": "REJECTED",
                          "reasons": ["arguments_not_accepted"]}, sort_keys=True) + "\n")
        return 2
    try:
        result = diagnose(run_query)
    except Exception:
        result = _result("INCONCLUSIVE", {"internal_error"}, [], _unknown_jobs("internal error"), {"complete": False})
    write(json.dumps(result, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
