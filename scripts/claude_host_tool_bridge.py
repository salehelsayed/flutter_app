#!/usr/bin/env python3
"""Host tool bridge for Claude Code running inside Docker on macOS.

The Claude Docker container is Linux, so it cannot execute macOS binaries such as
`xcrun`, `xcodebuild`, or a Flutter SDK installed on the Mac.  This bridge lets
small shims inside the container ask a short-lived localhost server (started by
scripts/run_claude_docker.sh on the Mac host) to run selected host tools from the
real repo checkout.  That gives Claude access to host Flutter/Xcode/devicectl and
USB-connected iPhones without mounting broad host directories into the container.
"""

from __future__ import annotations

import argparse
import hashlib
import http.client
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from typing import Any
import urllib.parse
import urllib.request

DEFAULT_ALLOWED_TOOLS = (
    "flutter",
    "dart",
    "xcrun",
    "xcodebuild",
    "pod",
    "adb",
    "ios-deploy",
    "idevice_id",
    "ideviceinstaller",
)

CONTAINER_REPO_ROOT = os.environ.get("CLAUDE_CONTAINER_REPO_ROOT", "/workspace")
SHARED_TMP_ROOT = f"{CONTAINER_REPO_ROOT}/.claude-host-tmp"


def _json_response(handler: http.server.BaseHTTPRequestHandler, status: int, payload: dict[str, Any]) -> None:
    body = json.dumps(payload).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def _read_local_properties(repo_root: Path) -> dict[str, str]:
    props: dict[str, str] = {}
    path = repo_root / "android" / "local.properties"
    if not path.exists():
        return props
    for raw_line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        props[key.strip()] = value.strip()
    return props


def _host_env(repo_root: Path) -> dict[str, str]:
    env = os.environ.copy()
    env["CLAUDE_HOST_REPO_ROOT"] = str(repo_root.resolve())
    env["CLAUDE_HOST_SHARED_TMP_ROOT"] = str((repo_root / ".claude-host-tmp").resolve())
    props = _read_local_properties(repo_root)
    path_entries: list[str] = []

    flutter_sdk = props.get("flutter.sdk")
    if flutter_sdk:
        path_entries.extend([
            f"{flutter_sdk}/bin",
            f"{flutter_sdk}/bin/cache/dart-sdk/bin",
        ])
        env.setdefault("FLUTTER_ROOT", flutter_sdk)

    android_sdk = props.get("sdk.dir")
    if android_sdk:
        env.setdefault("ANDROID_HOME", android_sdk)
        env.setdefault("ANDROID_SDK_ROOT", android_sdk)
        path_entries.extend([
            f"{android_sdk}/platform-tools",
            f"{android_sdk}/cmdline-tools/latest/bin",
            f"{android_sdk}/tools/bin",
        ])

    # Non-login shells launched from GUI apps often miss Homebrew and Xcode's
    # normal locations.  Keep inherited PATH too, but make common macOS developer
    # tool locations discoverable for `flutter`, `pod`, and friends.
    path_entries.extend([
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ])
    inherited = env.get("PATH")
    if inherited:
        path_entries.append(inherited)
    env["PATH"] = ":".join(dict.fromkeys(path_entries))
    return env


def _is_relative_to(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def _map_container_path(value: str, *, host_repo_root: Path, container_repo_root: str) -> str:
    if value == container_repo_root:
        return str(host_repo_root)
    prefix = f"{container_repo_root}/"
    if value.startswith(prefix):
        return str(host_repo_root / value[len(prefix):])
    return value


def _map_argv(argv: list[str], *, host_repo_root: Path, container_repo_root: str) -> list[str]:
    return [
        _map_container_path(arg, host_repo_root=host_repo_root, container_repo_root=container_repo_root)
        for arg in argv
    ]


def _map_cwd(cwd: str | None, *, host_repo_root: Path, container_repo_root: str) -> Path:
    if not cwd:
        return host_repo_root
    mapped = Path(_map_container_path(cwd, host_repo_root=host_repo_root, container_repo_root=container_repo_root))
    if _is_relative_to(mapped, host_repo_root):
        return mapped
    return host_repo_root


def _first_shell_script_arg(argv: list[str]) -> str | None:
    # Allow `host-run bash ./repo-script.sh ...` and `host-run bash -x ./script.sh`,
    # but deliberately reject `bash -lc ...`: that is arbitrary host shell access,
    # not "execute a script within this directory".
    for arg in argv[1:]:
        if arg in {"-c", "-lc", "-cl"}:
            return None
        if arg.startswith("-"):
            continue
        return arg
    return None


def _allowed_invocation(argv: list[str], *, cwd: Path, host_repo_root: Path, allowed_tools: set[str], env: dict[str, str]) -> tuple[bool, str]:
    if not argv:
        return False, "empty command"

    exe = Path(argv[0]).name
    if exe in allowed_tools:
        return True, "allowed host tool"

    if exe in {"bash", "sh", "zsh"}:
        script_arg = _first_shell_script_arg(argv)
        if script_arg is None:
            return False, "shell commands must name a script file inside the repo"
        script_path = Path(script_arg)
        if not script_path.is_absolute():
            script_path = cwd / script_path
        if _is_relative_to(script_path, host_repo_root):
            return True, "allowed repo shell script"
        return False, "shell script is outside the repo"

    resolved: Path | None = None
    if os.sep in argv[0]:
        candidate = Path(argv[0])
        if not candidate.is_absolute():
            candidate = cwd / candidate
        resolved = candidate
    else:
        found = shutil.which(argv[0], path=env.get("PATH"))
        if found:
            resolved = Path(found)

    if resolved is not None and _is_relative_to(resolved, host_repo_root):
        return True, "allowed repo executable"

    return False, f"{argv[0]!r} is not an allowed host tool or repo script"


class BridgeServer(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, server_address: tuple[str, int], handler: type[http.server.BaseHTTPRequestHandler], *, token: str, repo_root: Path, container_repo_root: str, allowed_tools: set[str]):
        super().__init__(server_address, handler)
        self.token = token
        self.repo_root = repo_root.resolve()
        self.container_repo_root = container_repo_root
        self.allowed_tools = allowed_tools
        self.host_env = _host_env(self.repo_root)


class BridgeHandler(http.server.BaseHTTPRequestHandler):
    server: BridgeServer

    def log_message(self, fmt: str, *args: Any) -> None:  # keep Claude's terminal clean
        return

    def do_GET(self) -> None:  # noqa: N802 - stdlib callback name
        if self.path == "/health":
            _json_response(self, 200, {"ok": True})
            return
        _json_response(self, 404, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802 - stdlib callback name
        if self.path != "/run":
            _json_response(self, 404, {"error": "not found"})
            return
        if self.headers.get("X-Claude-Host-Bridge-Token") != self.server.token:
            _json_response(self, 403, {"error": "invalid token"})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            raw_argv = payload.get("argv")
            if not isinstance(raw_argv, list) or not all(isinstance(arg, str) for arg in raw_argv):
                raise ValueError("argv must be a string array")
            raw_cwd = payload.get("cwd")
            if raw_cwd is not None and not isinstance(raw_cwd, str):
                raise ValueError("cwd must be a string")
        except Exception as exc:  # pragma: no cover - defensive parsing path
            _json_response(self, 400, {"error": str(exc)})
            return

        argv = _map_argv(
            raw_argv,
            host_repo_root=self.server.repo_root,
            container_repo_root=self.server.container_repo_root,
        )
        cwd = _map_cwd(
            raw_cwd,
            host_repo_root=self.server.repo_root,
            container_repo_root=self.server.container_repo_root,
        )

        allowed, reason = _allowed_invocation(
            argv,
            cwd=cwd,
            host_repo_root=self.server.repo_root,
            allowed_tools=self.server.allowed_tools,
            env=self.server.host_env,
        )
        if not allowed:
            _json_response(self, 403, {"error": reason, "returncode": 126})
            return

        started = time.time()
        try:
            completed = subprocess.run(
                argv,
                cwd=str(cwd),
                env=self.server.host_env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                errors="replace",
                check=False,
            )
            _json_response(
                self,
                200,
                {
                    "returncode": completed.returncode,
                    "stdout": completed.stdout,
                    "stderr": completed.stderr,
                    "host_cwd": str(cwd),
                    "reason": reason,
                    "duration_seconds": round(time.time() - started, 3),
                },
            )
        except FileNotFoundError as exc:
            _json_response(self, 200, {"returncode": 127, "stdout": "", "stderr": f"{exc}\n"})
        except Exception as exc:  # pragma: no cover - defensive execution path
            _json_response(self, 500, {"returncode": 1, "stdout": "", "stderr": f"{type(exc).__name__}: {exc}\n"})


def _rewrite_tmp_argument(arg: str) -> str:
    if not arg.startswith("/tmp/"):
        return arg

    original = Path(arg)
    digest = hashlib.sha256(arg.encode("utf-8")).hexdigest()[:16]
    shared = Path(SHARED_TMP_ROOT) / f"{digest}-{original.name}"
    shared.parent.mkdir(parents=True, exist_ok=True)

    if original.exists() and not original.is_symlink() and original.is_file() and original.stat().st_size > 0:
        shutil.copy2(original, shared)
    elif not shared.exists():
        shared.touch()

    try:
        if original.exists() or original.is_symlink():
            if original.is_dir():
                return str(shared)
            original.unlink()
        original.symlink_to(shared)
    except OSError:
        # If /tmp cannot be rewritten for some reason, still run the host command
        # with the shared path.  The command succeeds; the caller just will not be
        # able to read the original /tmp path through a symlink.
        pass
    return str(shared)


def client(argv: list[str]) -> int:
    if not argv:
        print("usage: host-run <tool-or-repo-script> [args...]", file=sys.stderr)
        return 2
    url = os.environ.get("CLAUDE_HOST_BRIDGE_URL")
    token = os.environ.get("CLAUDE_HOST_BRIDGE_TOKEN")
    if not url or not token:
        print(
            "Claude host bridge is not enabled. Start via scripts/run_claude_docker.sh "
            "with CLAUDE_DOCKER_ENABLE_HOST_TOOLS=1.",
            file=sys.stderr,
        )
        return 127

    rewritten_argv = [_rewrite_tmp_argument(arg) for arg in argv]
    body = json.dumps({"argv": rewritten_argv, "cwd": os.getcwd()}).encode("utf-8")
    request = urllib.request.Request(
        urllib.parse.urljoin(url.rstrip("/") + "/", "run"),
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "X-Claude-Host-Bridge-Token": token,
        },
    )

    try:
        with urllib.request.urlopen(request) as response:  # noqa: S310 - local token-auth bridge
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        try:
            payload = json.loads(exc.read().decode("utf-8"))
        except Exception:
            payload = {"error": str(exc), "returncode": 1}
    except Exception as exc:
        print(f"Claude host bridge request failed: {exc}", file=sys.stderr)
        return 127

    stdout = payload.get("stdout", "")
    stderr = payload.get("stderr", "")
    if stdout:
        print(stdout, end="")
    if stderr:
        print(stderr, end="", file=sys.stderr)
    if "error" in payload and not stderr:
        print(f"Claude host bridge denied command: {payload['error']}", file=sys.stderr)
    return int(payload.get("returncode", 1))


def serve(args: argparse.Namespace) -> int:
    repo_root = Path(args.repo_root).resolve()
    allowed_tools = set(args.allow_tool or DEFAULT_ALLOWED_TOOLS)
    server = BridgeServer(
        (args.bind, args.port),
        BridgeHandler,
        token=args.token,
        repo_root=repo_root,
        container_repo_root=args.container_repo_root,
        allowed_tools=allowed_tools,
    )
    # Print the selected port for humans/logs. run_claude_docker.sh normally
    # picks the port before launch, so it does not need to parse this.
    print(f"claude host bridge listening on {server.server_address[0]}:{server.server_address[1]}", flush=True)
    server.serve_forever(poll_interval=0.5)
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    serve_parser = subparsers.add_parser("serve")
    serve_parser.add_argument("--bind", default="127.0.0.1")
    serve_parser.add_argument("--port", type=int, required=True)
    serve_parser.add_argument("--token", required=True)
    serve_parser.add_argument("--repo-root", required=True)
    serve_parser.add_argument("--container-repo-root", default=CONTAINER_REPO_ROOT)
    serve_parser.add_argument("--allow-tool", action="append", default=[])

    client_parser = subparsers.add_parser("client")
    client_parser.add_argument("argv", nargs=argparse.REMAINDER)

    args = parser.parse_args(argv)
    if args.command == "serve":
        return serve(args)
    if args.command == "client":
        return client(args.argv)
    raise AssertionError(args.command)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
