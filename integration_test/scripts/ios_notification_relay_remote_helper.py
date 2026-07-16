"""Dependency-free remote half of the iOS notification relay fixture.

The local driver sends this source and one private request over SSH stdin. The
helper reads the deployed relay environment itself, speaks RESP directly to
Redis, and writes only a secret-free result to stdout. It is intentionally not
installed on the relay and has no third-party Python dependencies.
"""

from __future__ import annotations

import base64
import hashlib
import json
from pathlib import Path
import re
import shlex
import socket
import ssl
import subprocess
import sys
import time
from typing import Any, Mapping
from urllib.parse import unquote, urlparse


REQUEST_SCHEMA = "mknoon.sims.ios-payload-relay-remote-request.v1"
RESULT_SCHEMA = "mknoon.sims.ios-payload-relay-remote-result.v1"
RELAY_ENV_PATH = Path("/etc/mknoon/relay-server.env")
RELAY_BINARY_PATH = Path("/usr/local/bin/relay-server")
DEFAULT_INBOX_CAPACITY = 100
_SHA256 = re.compile(r"^[0-9a-f]{64}$")
_SAFE_TOKEN = re.compile(r"^[A-Za-z0-9._:@+-]{4,256}$")
_RELAY_REVISION = re.compile(r"^v[0-9A-Za-z][0-9A-Za-z._+-]{0,127}$")
_LIVE_RELAY_VERSION = re.compile(r"^relay-server (v[0-9A-Za-z][0-9A-Za-z._+-]{0,127})$")
_BASE58 = r"[1-9A-HJ-NP-Za-km-z]"
_PEER_ID = re.compile(rf"^(?:12D3KooW{_BASE58}{{44}}|Qm{_BASE58}{{44}})$")
_REQUEST_KEYS = frozenset(
    {
        "schema",
        "action",
        "runId",
        "nonce",
        "peerDeviceId",
        "senderPeerId",
        "entryId",
        "encryptedEnvelope",
        "apnsPayloadSha256",
        "encryptedEnvelopeSha256",
        "stagedEnvelopeSha256",
        "expectedRelayRevision",
        "expectedRelaySha256",
    }
)
_ENVELOPE_KEYS = frozenset({"type", "version", "id", "senderPeerId", "encrypted"})
_ENCRYPTED_KEYS = frozenset({"kem", "ciphertext", "nonce"})


class RemoteBlocked(Exception):
    """The live deployment/configuration cannot safely host the fixture."""


class RemoteFailure(Exception):
    """The requested mutation failed or would touch unrelated custody."""


class _RedisProtocolError(Exception):
    pass


def _canonical(value: object) -> str:
    return json.dumps(value, separators=(",", ":"), sort_keys=True)


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _sha256_text(value: str) -> str:
    return _sha256_bytes(value.encode("utf-8"))


def _stable_entry_id(run_id: str, nonce: str, peer_id: str) -> str:
    digest = _sha256_text("\x00".join((run_id, nonce, peer_id)))
    return f"sims-ios-relay-{digest[:32]}"


def _unique_json_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def _relay_revision_matches(expected: object, actual_output: object) -> bool:
    if not isinstance(expected, str) or _RELAY_REVISION.fullmatch(expected) is None:
        return False
    if not isinstance(actual_output, str):
        return False
    match = _LIVE_RELAY_VERSION.fullmatch(actual_output.strip())
    return match is not None and match.group(1) == expected


def _redis_component(value: str) -> str:
    return base64.urlsafe_b64encode(value.encode("utf-8")).rstrip(b"=").decode("ascii")


def _parse_env_value(raw: str) -> str:
    lexer = shlex.shlex(raw, posix=True)
    lexer.whitespace_split = True
    lexer.commenters = "#"
    try:
        words = list(lexer)
    except ValueError as error:
        raise RemoteBlocked("relay environment is malformed") from error
    if len(words) > 1:
        raise RemoteBlocked("relay environment contains an unsupported value")
    return words[0] if words else ""


def load_relay_environment(path: Path = RELAY_ENV_PATH) -> dict[str, str]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as error:
        raise RemoteBlocked("relay environment is unavailable") from error
    result: dict[str, str] = {}
    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].lstrip()
        key, separator, raw_value = line.partition("=")
        key = key.strip()
        if not separator or re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key) is None:
            raise RemoteBlocked("relay environment is malformed")
        result[key] = _parse_env_value(raw_value.strip())
    return result


class RedisConnection:
    """Small RESP2 client supporting only the commands used by this helper."""

    def __init__(self, raw_url: str):
        parsed = urlparse(raw_url)
        if parsed.scheme not in {"redis", "rediss"} or not parsed.hostname:
            raise RemoteBlocked("relay Redis endpoint is invalid")
        try:
            port = parsed.port or (6380 if parsed.scheme == "rediss" else 6379)
        except ValueError as error:
            raise RemoteBlocked("relay Redis endpoint is invalid") from error
        try:
            raw_socket = socket.create_connection((parsed.hostname, port), timeout=8)
            raw_socket.settimeout(8)
            if parsed.scheme == "rediss":
                context = ssl.create_default_context()
                self._socket = context.wrap_socket(
                    raw_socket,
                    server_hostname=parsed.hostname,
                )
            else:
                self._socket = raw_socket
            self._reader = self._socket.makefile("rb")
        except OSError as error:
            raise RemoteBlocked("relay Redis endpoint is unavailable") from error

        username = unquote(parsed.username) if parsed.username is not None else None
        password = unquote(parsed.password) if parsed.password is not None else None
        if password is not None:
            auth = self.command("AUTH", username or "default", password)
            if auth != "OK":
                raise RemoteBlocked("relay Redis authentication failed")
        elif username is not None:
            raise RemoteBlocked("relay Redis credentials are incomplete")

        database_text = parsed.path.lstrip("/")
        if database_text:
            if not database_text.isdigit():
                raise RemoteBlocked("relay Redis database is invalid")
            selected = self.command("SELECT", database_text)
            if selected != "OK":
                raise RemoteBlocked("relay Redis database selection failed")

    def close(self) -> None:
        try:
            self._reader.close()
        finally:
            self._socket.close()

    def command(self, *parts: object) -> Any:
        encoded = bytearray(f"*{len(parts)}\r\n".encode("ascii"))
        for part in parts:
            value = part if isinstance(part, bytes) else str(part).encode("utf-8")
            encoded.extend(f"${len(value)}\r\n".encode("ascii"))
            encoded.extend(value)
            encoded.extend(b"\r\n")
        try:
            self._socket.sendall(encoded)
            return self._read_response()
        except (OSError, UnicodeError, _RedisProtocolError) as error:
            raise RemoteFailure("relay Redis operation failed") from error

    def _line(self) -> bytes:
        line = self._reader.readline()
        if not line.endswith(b"\r\n"):
            raise _RedisProtocolError("truncated response")
        return line[:-2]

    def _read_response(self) -> Any:
        prefix = self._reader.read(1)
        if prefix == b"+":
            return self._line().decode("utf-8")
        if prefix == b"-":
            self._line()
            raise _RedisProtocolError("Redis error")
        if prefix == b":":
            return int(self._line())
        if prefix == b"$":
            length = int(self._line())
            if length == -1:
                return None
            value = self._reader.read(length)
            if len(value) != length or self._reader.read(2) != b"\r\n":
                raise _RedisProtocolError("truncated bulk response")
            return value.decode("utf-8")
        if prefix == b"*":
            count = int(self._line())
            if count == -1:
                return None
            return [self._read_response() for _ in range(count)]
        raise _RedisProtocolError("unsupported response")


def _validated_request(raw: bytes) -> dict[str, Any]:
    try:
        decoded = json.loads(
            raw.decode("utf-8"),
            object_pairs_hook=_unique_json_object,
        )
    except (UnicodeError, json.JSONDecodeError, ValueError) as error:
        raise RemoteFailure("remote fixture request is invalid") from error
    if (
        not isinstance(decoded, dict)
        or frozenset(decoded) != _REQUEST_KEYS
        or decoded.get("schema") != REQUEST_SCHEMA
    ):
        raise RemoteFailure("remote fixture request is invalid")
    for key in ("runId", "nonce"):
        if not isinstance(decoded.get(key), str) or _SAFE_TOKEN.fullmatch(decoded[key]) is None:
            raise RemoteFailure("remote fixture binding is invalid")
    for key in ("peerDeviceId", "senderPeerId"):
        if not isinstance(decoded.get(key), str) or _PEER_ID.fullmatch(decoded[key]) is None:
            raise RemoteFailure("remote fixture peer identity is invalid")
    if decoded.get("action") not in {"setup", "cleanup", "rollback"}:
        raise RemoteFailure("remote fixture action is invalid")
    for key in (
        "apnsPayloadSha256",
        "encryptedEnvelopeSha256",
        "stagedEnvelopeSha256",
        "expectedRelaySha256",
    ):
        if not isinstance(decoded.get(key), str) or _SHA256.fullmatch(decoded[key]) is None:
            raise RemoteFailure("remote fixture digest is invalid")
    revision = decoded.get("expectedRelayRevision")
    envelope_text = decoded.get("encryptedEnvelope")
    if not isinstance(revision, str) or _RELAY_REVISION.fullmatch(revision) is None:
        raise RemoteFailure("remote relay revision binding is invalid")
    if not isinstance(envelope_text, str) or len(envelope_text) > 32768:
        raise RemoteFailure("remote encrypted envelope is invalid")
    try:
        envelope = json.loads(
            envelope_text,
            object_pairs_hook=_unique_json_object,
        )
    except (json.JSONDecodeError, ValueError) as error:
        raise RemoteFailure("remote encrypted envelope is invalid") from error
    if not isinstance(envelope, dict) or frozenset(envelope) != _ENVELOPE_KEYS:
        raise RemoteFailure("remote encrypted envelope is invalid")
    encrypted = envelope.get("encrypted")
    if (
        envelope.get("type") != "chat_message"
        or envelope.get("version") != "2"
        or not isinstance(envelope.get("id"), str)
        or envelope.get("senderPeerId") != decoded["senderPeerId"]
        or not isinstance(encrypted, dict)
        or frozenset(encrypted) != _ENCRYPTED_KEYS
        or any(not isinstance(encrypted.get(key), str) or not encrypted[key] for key in ("kem", "ciphertext", "nonce"))
    ):
        raise RemoteFailure("remote encrypted envelope is invalid")
    canonical_envelope = _canonical(envelope)
    if canonical_envelope != envelope_text or _sha256_text(envelope_text) != decoded["encryptedEnvelopeSha256"]:
        raise RemoteFailure("remote encrypted envelope digest does not match")
    expected_entry_id = _stable_entry_id(decoded["runId"], decoded["nonce"], decoded["peerDeviceId"])
    if decoded.get("entryId") != expected_entry_id:
        raise RemoteFailure("remote fixture entry identity is invalid")
    return decoded


def _verify_live_relay(request: Mapping[str, Any]) -> tuple[str, str]:
    try:
        active = subprocess.run(
            ["systemctl", "is-active", "relay-server"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        version = subprocess.run(
            [str(RELAY_BINARY_PATH), "version"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        binary = RELAY_BINARY_PATH.read_bytes()
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RemoteBlocked("live relay attestation is unavailable") from error
    actual_revision = version.stdout.strip()
    actual_sha = _sha256_bytes(binary)
    if (
        active.returncode != 0
        or active.stdout.strip() != "active"
        or version.returncode != 0
        or not _relay_revision_matches(request["expectedRelayRevision"], actual_revision)
        or request["expectedRelaySha256"] != actual_sha
    ):
        raise RemoteBlocked("live relay does not match staging attestation")
    return actual_revision, actual_sha


def _verify_live_process_environment(environment: Mapping[str, str]) -> None:
    """Prove the running service inherited the same private env we will use."""

    try:
        environment_files = subprocess.run(
            ["systemctl", "show", "relay-server", "--property=EnvironmentFiles", "--value"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        main_pid = subprocess.run(
            ["systemctl", "show", "relay-server", "--property=MainPID", "--value"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        pid_text = main_pid.stdout.strip()
        if (
            environment_files.returncode != 0
            or str(RELAY_ENV_PATH) not in environment_files.stdout
            or main_pid.returncode != 0
            or not pid_text.isdigit()
            or int(pid_text) <= 1
        ):
            raise RemoteBlocked("live relay environment attestation is unavailable")
        raw_process_environment = Path(f"/proc/{pid_text}/environ").read_bytes()
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RemoteBlocked("live relay environment attestation is unavailable") from error
    process_environment: dict[str, str] = {}
    for item in raw_process_environment.split(b"\x00"):
        key, separator, value = item.partition(b"=")
        if not separator:
            continue
        try:
            process_environment[key.decode("utf-8")] = value.decode("utf-8")
        except UnicodeError:
            continue
    for key in ("RELAY_BACKEND", "REDIS_URL"):
        if not environment.get(key) or process_environment.get(key) != environment[key]:
            raise RemoteBlocked("running relay environment does not match its private file")
    for key in ("REDIS_PREFIX", "RELAY_MAX_INBOX_MESSAGES_PER_PEER"):
        if key in environment and process_environment.get(key) != environment[key]:
            raise RemoteBlocked("running relay environment does not match its private file")


def _capacity(environment: Mapping[str, str]) -> int:
    raw = environment.get("RELAY_MAX_INBOX_MESSAGES_PER_PEER", "").strip()
    if not raw:
        return DEFAULT_INBOX_CAPACITY
    try:
        parsed = int(raw)
    except ValueError:
        return DEFAULT_INBOX_CAPACITY
    return parsed if parsed > 0 else DEFAULT_INBOX_CAPACITY


def _entry_shape(raw: str) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    try:
        outer = json.loads(raw)
        if not isinstance(outer, dict):
            return None, None
        envelope = json.loads(outer.get("message", ""))
        if not isinstance(envelope, dict):
            envelope = None
        return outer, envelope
    except (TypeError, json.JSONDecodeError):
        return None, None


def _classify_entries(
    raw_entries: list[str],
    request: Mapping[str, Any],
) -> tuple[list[str], bool]:
    exact: list[str] = []
    conflict = False
    expected_message_id = json.loads(request["encryptedEnvelope"])["id"]
    for raw in raw_entries:
        outer, envelope = _entry_shape(raw)
        if outer is None:
            continue
        same_entry_id = outer.get("id") == request["entryId"]
        exact_shape = (
            same_entry_id
            and outer.get("from") == request["senderPeerId"]
            and outer.get("message") == request["encryptedEnvelope"]
            and isinstance(outer.get("timestamp"), int)
        )
        if exact_shape:
            exact.append(raw)
            continue
        same_message_id = isinstance(envelope, dict) and envelope.get("id") == expected_message_id
        if same_entry_id or same_message_id:
            conflict = True
    return exact, conflict


def _unwatch(redis: RedisConnection) -> None:
    try:
        redis.command("UNWATCH")
    except RemoteFailure:
        pass


def seed_exact_entry(
    redis: RedisConnection,
    key: str,
    request: Mapping[str, Any],
    capacity: int,
) -> tuple[str, bool]:
    entry = {
        "id": request["entryId"],
        "from": request["senderPeerId"],
        "message": request["encryptedEnvelope"],
        "timestamp": int(time.time() * 1000),
    }
    raw_entry = _canonical(entry)
    for _ in range(8):
        redis.command("WATCH", key)
        raw_entries = redis.command("LRANGE", key, 0, -1)
        if not isinstance(raw_entries, list) or any(not isinstance(value, str) for value in raw_entries):
            _unwatch(redis)
            raise RemoteFailure("relay inbox response is invalid")
        exact, conflict = _classify_entries(raw_entries, request)
        if conflict or len(exact) > 1:
            _unwatch(redis)
            raise RemoteFailure("fixture identity conflicts with existing relay custody")
        if len(exact) == 1:
            _unwatch(redis)
            return _sha256_text(exact[0]), False
        if len(raw_entries) >= capacity:
            _unwatch(redis)
            raise RemoteFailure("fixture could evict unrelated relay custody")
        if redis.command("MULTI") != "OK":
            raise RemoteFailure("relay inbox transaction could not start")
        if redis.command("RPUSH", key, raw_entry) != "QUEUED":
            raise RemoteFailure("relay inbox append was not queued")
        committed = redis.command("EXEC")
        if committed is None:
            continue
        if not isinstance(committed, list) or len(committed) != 1:
            raise RemoteFailure("relay inbox append transaction was invalid")
        return _sha256_text(raw_entry), True
    raise RemoteFailure("relay inbox changed concurrently too many times")


def clear_exact_entry(
    redis: RedisConnection,
    key: str,
    request: Mapping[str, Any],
) -> tuple[str | None, int]:
    for _ in range(8):
        redis.command("WATCH", key)
        raw_entries = redis.command("LRANGE", key, 0, -1)
        if not isinstance(raw_entries, list) or any(not isinstance(value, str) for value in raw_entries):
            _unwatch(redis)
            raise RemoteFailure("relay inbox response is invalid")
        exact, conflict = _classify_entries(raw_entries, request)
        if conflict or len(exact) > 1:
            _unwatch(redis)
            raise RemoteFailure("fixture identity conflicts with existing relay custody")
        if not exact:
            _unwatch(redis)
            return None, 0
        exact_raw = exact[0]
        if redis.command("MULTI") != "OK":
            raise RemoteFailure("relay inbox transaction could not start")
        if redis.command("LREM", key, 1, exact_raw) != "QUEUED":
            raise RemoteFailure("relay inbox exact removal was not queued")
        committed = redis.command("EXEC")
        if committed is None:
            continue
        if not isinstance(committed, list) or committed != [1]:
            raise RemoteFailure("relay inbox exact removal was not singular")
        return _sha256_text(exact_raw), 1
    raise RemoteFailure("relay inbox changed concurrently too many times")


def run_remote(request_bytes: bytes) -> dict[str, Any]:
    request = _validated_request(request_bytes)
    live_revision, live_sha = _verify_live_relay(request)
    environment = load_relay_environment()
    _verify_live_process_environment(environment)
    if environment.get("RELAY_BACKEND", "").strip().lower() != "redis":
        raise RemoteBlocked("live relay does not use durable Redis custody")
    prefix = environment.get("REDIS_PREFIX", "relay:").strip() or "relay:"
    if not prefix.endswith(":"):
        prefix += ":"
    if prefix != "relay:":
        raise RemoteBlocked("live relay Redis prefix does not match the fixture contract")
    redis_url = environment.get("REDIS_URL", "").strip()
    if not redis_url:
        raise RemoteBlocked("live relay Redis endpoint is unavailable")

    key = "relay:inbox:" + _redis_component(request["peerDeviceId"])
    redis = RedisConnection(redis_url)
    try:
        if request["action"] == "setup":
            entry_sha, mutated = seed_exact_entry(redis, key, request, _capacity(environment))
            status = "seeded"
            removed = 0
        else:
            entry_sha, removed = clear_exact_entry(redis, key, request)
            mutated = removed == 1
            status = "cleared"
    finally:
        redis.close()

    result: dict[str, Any] = {
        "schema": RESULT_SCHEMA,
        "action": request["action"],
        "status": status,
        "mutated": mutated,
        "removedCount": removed,
        "apnsPayloadSha256": request["apnsPayloadSha256"],
        "encryptedEnvelopeSha256": request["encryptedEnvelopeSha256"],
        "stagedEnvelopeSha256": request["stagedEnvelopeSha256"],
        "liveRelayRevisionSha256": _sha256_text(live_revision),
        "liveRelaySha256": live_sha,
    }
    if entry_sha is not None:
        result["relayEntrySha256"] = entry_sha
    return result


def remote_cli(request_bytes: bytes) -> None:
    try:
        result = run_remote(request_bytes)
    except RemoteBlocked:
        print("iOS relay fixture remote helper blocked", file=sys.stderr)
        raise SystemExit(78)
    except (RemoteFailure, Exception):
        print("iOS relay fixture remote helper failed", file=sys.stderr)
        raise SystemExit(1)
    print(_canonical(result))
