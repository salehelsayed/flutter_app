#!/usr/bin/env python3
"""Fail-closed relay/APNs adapter for the physical-iPhone SIMS proof.

All mutation is guarded by a private lifecycle record. The exact <=4096-byte
payload snapshot given to the relay fixture is also the exact file submitted to
APNs. Setup failures, timeouts, and signals enter the same idempotent rollback
path exposed publicly as ``--action rollback``.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
from typing import Any, Iterable, Mapping, NoReturn
import unicodedata


BUNDLE_ID = "com.mknoon.app"
SCENARIO = "payload_fast_path_ios_receiver"
EXPECTED_APNS_ENVIRONMENT = "development"
STAGING_SCHEMA = "mknoon.sims.ios-payload-fast-path-staging.v1"
PROVIDER_REQUEST_SCHEMA = (
    "mknoon.sims.ios-payload-fast-path-provider-request.v1"
)
PROVIDER_RECEIPT_SCHEMA = (
    "mknoon.sims.ios-payload-fast-path-provider-receipt.v1"
)
CLEANUP_RECEIPT_SCHEMA = (
    "mknoon.sims.ios-payload-fast-path-provider-cleanup-receipt.v1"
)
RECOVERY_RECEIPT_SCHEMA = (
    "mknoon.sims.ios-payload-fast-path-provider-recovery-receipt.v1"
)
RELAY_FIXTURE_RECEIPT_SCHEMA = (
    "mknoon.sims.ios-payload-relay-fixture-receipt.v1"
)
RECEIVER_HANDOFF_SCHEMA = "mknoon.sims.ios-provider-receiver-handoff.v2"
LIFECYCLE_SCHEMA = "mknoon.sims.ios-provider-lifecycle.v1"
APNS_HOSTS = {
    "development": "https://api.sandbox.push.apple.com",
}
APNS_DELIVERY_WINDOW_SECONDS = 120

_SHA256 = re.compile(r"^[0-9a-f]{64}$")
_SAFE_TOKEN = re.compile(r"^[A-Za-z0-9._:@+-]{4,256}$")
_RELAY_REVISION = re.compile(r"^v[0-9A-Za-z][0-9A-Za-z._+-]{0,127}$")
_RECEIVER_ID = re.compile(r"^[A-Za-z0-9._:-]{4,160}$")
_BASE58 = r"[1-9A-HJ-NP-Za-km-z]"
_TRANSPORT_PEER_ID = re.compile(
    rf"^(?:12D3KooW{_BASE58}{{44}}|Qm{_BASE58}{{44}})$"
)
_KEY_ID = re.compile(r"^[A-Z0-9]{10}$")
_TEAM_ID = re.compile(r"^[A-Z0-9]{10}$")
_DEVICE_TOKEN = re.compile(r"^[0-9a-fA-F]{64,256}$")
_PUBLIC_KEY = re.compile(r"^[A-Za-z0-9_+/=-]{16,8192}$")
_FORBIDDEN_KEYS = {
    "token",
    "apnstoken",
    "devicetoken",
    "fcmtoken",
    "ciphertext",
    "privatekey",
    "secret",
    "secretkey",
    "mnemonic",
    "authorization",
    "password",
}
_APNS_CREDENTIAL_REASONS = {
    "BadCertificate",
    "BadCertificateEnvironment",
    "ExpiredProviderToken",
    "Forbidden",
    "InvalidProviderToken",
    "MissingProviderToken",
}
_APNS_HANDOFF_REASONS = {
    "BadDeviceToken",
    "DeviceTokenNotForTopic",
    "Unregistered",
}


class AdapterBlocked(Exception):
    """A missing or inconsistent private input (exit 78)."""


class AdapterFailure(Exception):
    """A configured provider, relay, disk, or device action failed (exit 1)."""


class CommandTimedOut(AdapterFailure):
    """A command and its descendant process group exceeded its deadline."""


class AdapterInterrupted(AdapterFailure):
    """The outer driver requested termination; setup must recover."""


class _DuplicateJsonKey(ValueError):
    pass


class CommandResult:
    def __init__(self, returncode: int, stdout: bytes, stderr: bytes) -> None:
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


class ReceiverHandoff:
    def __init__(self, value: Mapping[str, Any], digest: str) -> None:
        self.value = value
        self.digest = digest
        self.device_token = str(value["apnsDeviceToken"])
        self.mlkem_public_key = str(value["mlKemPublicKey"])


class ProviderContext:
    def __init__(
        self,
        *,
        args: argparse.Namespace,
        request: Mapping[str, Any],
        staging: Mapping[str, Any],
        handoff: ReceiverHandoff,
        signing_team_id: str,
        request_sha: str,
        staging_sha: str,
        payload_sha: str,
        staged_sha: str,
        state_directory: Path,
        payload_snapshot: Path,
        lifecycle: Path,
        initial_lifecycle_state: str | None,
    ) -> None:
        self.args = args
        self.request = request
        self.staging = staging
        self.handoff = handoff
        self.signing_team_id = signing_team_id
        self.request_sha = request_sha
        self.staging_sha = staging_sha
        self.payload_sha = payload_sha
        self.staged_sha = staged_sha
        self.state_directory = state_directory
        self.payload_snapshot = payload_snapshot
        self.lifecycle = lifecycle
        self.initial_lifecycle_state = initial_lifecycle_state


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _sha256_text(value: str) -> str:
    return _sha256_bytes(value.encode("utf-8"))


def _sha256_file(path: Path) -> str:
    return _sha256_bytes(path.read_bytes())


def _utc_now() -> str:
    return (
        datetime.datetime.now(datetime.timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z")
    )


def _utc_timestamp(value: object, label: str) -> datetime.datetime:
    if not isinstance(value, str) or not value.endswith("Z"):
        raise AdapterBlocked(f"{label} must be an explicit UTC timestamp")
    try:
        parsed = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise AdapterBlocked(f"{label} must be an explicit UTC timestamp") from error
    if parsed.utcoffset() != datetime.timedelta(0):
        raise AdapterBlocked(f"{label} must be an explicit UTC timestamp")
    return parsed


def is_transport_peer_id(value: object) -> bool:
    return isinstance(value, str) and _TRANSPORT_PEER_ID.fullmatch(value) is not None


def apns_host_for_manifest(staging: Mapping[str, Any]) -> str:
    environment = staging.get("apnsEnvironment")
    entitlement = staging.get("signingEntitlementEnvironment")
    if (
        environment != entitlement
        or environment != EXPECTED_APNS_ENVIRONMENT
        or environment not in APNS_HOSTS
    ):
        raise AdapterBlocked(
            "APNs endpoint, handoff, and signed-app entitlement must be development"
        )
    return APNS_HOSTS[str(environment)]


def _bounded_string(value: object, *, maximum: int = 512) -> bool:
    return (
        isinstance(value, str)
        and bool(value.strip())
        and len(value) <= maximum
        and "\n" not in value
        and "\r" not in value
    )


def _bounded_fixture_text(value: object, *, maximum: int) -> bool:
    return (
        isinstance(value, str)
        and value == value.strip()
        and bool(value)
        and len(value) <= maximum
        and all(0x20 <= ord(character) <= 0x7E for character in value)
    )


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, member in pairs:
        if key in value:
            raise _DuplicateJsonKey(key)
        value[key] = member
    return value


def decode_json_object_bytes(value: bytes, label: str) -> dict[str, Any]:
    try:
        decoded = json.loads(
            value.decode("utf-8"),
            object_pairs_hook=_reject_duplicate_pairs,
        )
    except (UnicodeError, json.JSONDecodeError, _DuplicateJsonKey) as error:
        raise AdapterBlocked(f"{label} is not duplicate-free valid JSON") from error
    if not isinstance(decoded, dict):
        raise AdapterBlocked(f"{label} must contain a JSON object")
    return decoded


def _read_json_object(path: Path, label: str) -> tuple[dict[str, Any], bytes]:
    try:
        raw = path.read_bytes()
    except OSError as error:
        raise AdapterBlocked(f"{label} is unreadable") from error
    return decode_json_object_bytes(raw, label), raw


def _private_regular_file(raw_path: str, label: str) -> Path:
    if not raw_path or "\n" in raw_path or "\r" in raw_path:
        raise AdapterBlocked(f"{label} path is unavailable")
    path = Path(raw_path).expanduser().absolute()
    try:
        metadata = path.lstat()
    except OSError as error:
        raise AdapterBlocked(f"{label} is unavailable") from error
    if not stat.S_ISREG(metadata.st_mode) or path.is_symlink():
        raise AdapterBlocked(f"{label} must be a non-symlink regular file")
    if hasattr(os, "getuid") and metadata.st_uid != os.getuid():
        raise AdapterBlocked(f"{label} must be owned by the current operator")
    if metadata.st_mode & 0o077:
        raise AdapterBlocked(f"{label} permissions must be owner-only")
    if metadata.st_size <= 0:
        raise AdapterBlocked(f"{label} is empty")
    return path


def _regular_file(raw_path: str, label: str) -> Path:
    if not raw_path or "\n" in raw_path or "\r" in raw_path:
        raise AdapterBlocked(f"{label} path is unavailable")
    path = Path(raw_path).expanduser().absolute()
    try:
        metadata = path.stat()
    except OSError as error:
        raise AdapterBlocked(f"{label} is unavailable") from error
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_size <= 0:
        raise AdapterBlocked(f"{label} must be a nonempty regular file")
    return path


def _operator_regular_file(raw_path: str, label: str) -> Path:
    if not raw_path or "\n" in raw_path or "\r" in raw_path:
        raise AdapterBlocked(f"{label} path is unavailable")
    path = Path(raw_path).expanduser().absolute()
    try:
        metadata = path.lstat()
    except OSError as error:
        raise AdapterBlocked(f"{label} is unavailable") from error
    if (
        not stat.S_ISREG(metadata.st_mode)
        or path.is_symlink()
        or metadata.st_size <= 0
    ):
        raise AdapterBlocked(f"{label} must be a nonempty non-symlink regular file")
    if hasattr(os, "getuid") and metadata.st_uid != os.getuid():
        raise AdapterBlocked(f"{label} must be owned by the current operator")
    return path


def _executable(raw_path: str, label: str) -> Path:
    path = _regular_file(raw_path, label)
    if not os.access(path, os.X_OK):
        raise AdapterBlocked(f"{label} must be executable")
    return path


def _resolved_executable(environment_name: str, default: str, label: str) -> Path:
    configured = os.environ.get(environment_name, "").strip()
    if configured:
        return _executable(configured, label)
    resolved = shutil.which(default)
    if resolved is None:
        raise AdapterBlocked(f"{label} is unavailable")
    return _executable(resolved, label)


def _minimal_environment(extra: Mapping[str, str] | None = None) -> dict[str, str]:
    environment: dict[str, str] = {}
    for key in ("PATH", "HOME", "TMPDIR", "LANG", "LC_ALL", "SSH_AUTH_SOCK"):
        value = os.environ.get(key)
        if value:
            environment[key] = value
    if extra:
        environment.update(extra)
    return environment


def _terminate_process_group(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    except OSError:
        process.terminate()
    try:
        process.wait(timeout=1.0)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        return
    except OSError:
        process.kill()
    try:
        process.wait(timeout=2.0)
    except subprocess.TimeoutExpired:
        pass


def run_process(
    arguments: list[str],
    *,
    timeout_seconds: float,
    environment: Mapping[str, str],
) -> CommandResult:
    process = subprocess.Popen(
        arguments,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=dict(environment),
        start_new_session=True,
    )
    try:
        stdout_value, stderr_value = process.communicate(timeout=timeout_seconds)
    except subprocess.TimeoutExpired as error:
        _terminate_process_group(process)
        process.communicate()
        raise CommandTimedOut("provider subprocess timed out") from error
    except BaseException:
        _terminate_process_group(process)
        process.communicate()
        raise
    return CommandResult(process.returncode, stdout_value, stderr_value)


def _timeout_seconds(name: str, default: int, maximum: int) -> float:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return float(default)
    try:
        value = float(raw)
    except ValueError as error:
        raise AdapterBlocked(f"{name} is invalid") from error
    if value < 1 or value > maximum:
        raise AdapterBlocked(f"{name} is outside its safe range")
    return value


def _walk_strings(
    value: object,
    path: tuple[str, ...] = (),
) -> Iterable[tuple[tuple[str, ...], str]]:
    if isinstance(value, dict):
        for key, member in value.items():
            yield from _walk_strings(member, (*path, str(key)))
    elif isinstance(value, list):
        for index, member in enumerate(value):
            yield from _walk_strings(member, (*path, str(index)))
    elif isinstance(value, str):
        yield path, value


def _normalized_plaintext(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value).casefold()
    return " ".join(normalized.split())


def _redact_allowed_alerts(
    value: object,
    path: tuple[str, ...] = (),
) -> object:
    if path in {("aps", "alert", "title"), ("aps", "alert", "body")}:
        return "<allowed-visible-alert>"
    if isinstance(value, dict):
        return {
            str(key): _redact_allowed_alerts(member, (*path, str(key)))
            for key, member in value.items()
        }
    if isinstance(value, list):
        return [
            _redact_allowed_alerts(member, (*path, str(index)))
            for index, member in enumerate(value)
        ]
    return value


def validate_apns_payload(
    payload: Mapping[str, Any],
    request: Mapping[str, Any],
    transmitted_bytes: bytes | None = None,
) -> str:
    if transmitted_bytes is None:
        transmitted_bytes = json.dumps(
            payload,
            separators=(",", ":"),
            ensure_ascii=False,
        ).encode("utf-8")
    if not transmitted_bytes or len(transmitted_bytes) > 4096:
        raise AdapterBlocked("actual APNs payload must contain at most 4096 bytes")
    aps = payload.get("aps")
    if not isinstance(aps, dict):
        raise AdapterBlocked("APNs payload has no aps object")
    alert = aps.get("alert")
    if not isinstance(alert, dict):
        raise AdapterBlocked("APNs payload has no visible alert")
    if (
        alert.get("title") != request.get("expectedTitle")
        or alert.get("body") != request.get("expectedBody")
    ):
        raise AdapterBlocked("APNs alert is not bound to the provider request")
    mutable = aps.get("mutable-content")
    if isinstance(mutable, bool) or mutable != 1:
        raise AdapterBlocked("APNs payload must invoke the notification extension")

    required_route = ("sender_id", "message_id", "kem", "ciphertext", "nonce")
    if payload.get("type") != "new_message" or any(
        not _bounded_string(payload.get(key), maximum=3072) for key in required_route
    ):
        raise AdapterBlocked("APNs payload has no complete encrypted chat route")
    if not is_transport_peer_id(payload.get("sender_id")):
        raise AdapterBlocked("APNs sender_id is not a transport peer identity")

    allowed = {
        ("aps", "alert", "title"): str(request["expectedTitle"]),
        ("aps", "alert", "body"): str(request["expectedBody"]),
    }
    sensitive = {
        _normalized_plaintext(str(request[key]))
        for key in ("expectedTitle", "expectedBody", "expectedMessageText")
        if _normalized_plaintext(str(request[key]))
    }
    for value_path, text in _walk_strings(payload):
        if value_path in allowed and text == allowed[value_path]:
            continue
        normalized = _normalized_plaintext(text)
        if any(needle in normalized for needle in sensitive):
            raise AdapterBlocked("APNs payload contains fixture plaintext outside alert")
    canonical_redacted = json.dumps(
        _redact_allowed_alerts(payload),
        separators=(",", ":"),
        sort_keys=True,
        ensure_ascii=False,
    )
    normalized_canonical = _normalized_plaintext(canonical_redacted)
    if any(needle in normalized_canonical for needle in sensitive):
        raise AdapterBlocked("canonical APNs payload contains fixture plaintext")

    staged = {
        "kind": "chat",
        "messageId": payload["message_id"],
        "kem": payload["kem"],
        "ciphertext": payload["ciphertext"],
        "nonce": payload["nonce"],
        "senderPeerId": payload["sender_id"],
    }
    canonical = json.dumps(staged, separators=(",", ":"), sort_keys=True).encode(
        "utf-8"
    )
    return _sha256_bytes(canonical)


def _secret_bearing_field(value: object, path: str = "$") -> str | None:
    if isinstance(value, dict):
        for key, member in value.items():
            name = str(key)
            normalized = re.sub(r"[^A-Za-z0-9]", "", name).lower()
            if normalized in _FORBIDDEN_KEYS and member is not None:
                return f"{path}.{name}"
            nested = _secret_bearing_field(member, f"{path}.{name}")
            if nested is not None:
                return nested
    elif isinstance(value, list):
        for index, member in enumerate(value):
            nested = _secret_bearing_field(member, f"{path}[{index}]")
            if nested is not None:
                return nested
    elif isinstance(value, str) and "BEGIN PRIVATE KEY" in value:
        return path
    return None


def _write_bytes_private(path: Path, value: bytes, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        dir=str(path.parent),
    )
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(value)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        path.chmod(mode)
    finally:
        if temporary.exists():
            temporary.unlink()


def _write_json_private(path: Path, value: Mapping[str, Any]) -> None:
    encoded = (json.dumps(value, separators=(",", ":"), sort_keys=True) + "\n").encode(
        "utf-8"
    )
    _write_bytes_private(path, encoded)


def _ensure_private_directory(path: Path) -> None:
    if path.exists():
        metadata = path.lstat()
        if not stat.S_ISDIR(metadata.st_mode) or path.is_symlink():
            raise AdapterBlocked("provider lifecycle path is unsafe")
        if hasattr(os, "getuid") and metadata.st_uid != os.getuid():
            raise AdapterBlocked("provider lifecycle path has the wrong owner")
        path.chmod(0o700)
        return
    path.mkdir(parents=True, mode=0o700)


def _validate_handoff(args: argparse.Namespace) -> ReceiverHandoff:
    handoff_path = _private_regular_file(
        os.environ.get("SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_PATH", "").strip(),
        "receiver handoff",
    )
    expected_nonce = os.environ.get(
        "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE", ""
    ).strip()
    if _SAFE_TOKEN.fullmatch(expected_nonce) is None:
        raise AdapterBlocked("receiver handoff nonce is unavailable or invalid")
    value, raw = _read_json_object(handoff_path, "receiver handoff")
    required = {
        "schema",
        "captureNonce",
        "receiverDeviceId",
        "peerDeviceId",
        "bundleId",
        "apnsEnvironment",
        "apnsDeviceToken",
        "mlKemPublicKey",
        "notificationAuthorization",
        "notificationAlertSetting",
        "notificationBadgeSetting",
        "capturedAt",
    }
    if set(value.keys()) != required:
        raise AdapterBlocked("receiver handoff fields are not exact")
    exact = {
        "schema": RECEIVER_HANDOFF_SCHEMA,
        "captureNonce": expected_nonce,
        "receiverDeviceId": args.receiver,
        "peerDeviceId": args.peer_device,
        "bundleId": BUNDLE_ID,
        "apnsEnvironment": EXPECTED_APNS_ENVIRONMENT,
    }
    if any(value.get(key) != member for key, member in exact.items()):
        raise AdapterBlocked("receiver handoff is not bound to this development run")
    if value.get("notificationAuthorization") not in {
        "authorized",
        "provisional",
        "ephemeral",
    } or value.get("notificationAlertSetting") != "enabled" or value.get(
        "notificationBadgeSetting"
    ) != "enabled":
        raise AdapterBlocked(
            "receiver handoff does not prove authorized alerts and badges"
        )
    token = str(value.get("apnsDeviceToken", ""))
    if _DEVICE_TOKEN.fullmatch(token) is None:
        raise AdapterBlocked("receiver handoff APNs token is invalid")
    try:
        token_bytes = bytes.fromhex(token)
    except ValueError as error:
        raise AdapterBlocked("receiver handoff APNs token is invalid") from error
    if len(token_bytes) != 32:
        raise AdapterBlocked("receiver handoff APNs token is not exactly 32 bytes")
    mlkem_public_key = str(value.get("mlKemPublicKey", ""))
    if _PUBLIC_KEY.fullmatch(mlkem_public_key) is None:
        raise AdapterBlocked("receiver handoff ML-KEM public key is invalid")
    try:
        mlkem_public_bytes = base64.b64decode(
            mlkem_public_key,
            altchars=b"-_",
            validate=True,
        )
    except (binascii.Error, ValueError, TypeError) as error:
        raise AdapterBlocked("receiver handoff ML-KEM public key is invalid") from error
    if len(mlkem_public_bytes) != 1184:
        raise AdapterBlocked(
            "receiver handoff ML-KEM public key is not exactly 1184 bytes"
        )
    captured = _utc_timestamp(value.get("capturedAt"), "receiver handoff capturedAt")
    age = datetime.datetime.now(datetime.timezone.utc) - captured
    if age < -datetime.timedelta(minutes=5) or age > datetime.timedelta(minutes=30):
        raise AdapterBlocked("receiver handoff is stale or from the future")
    return ReceiverHandoff(value, _sha256_bytes(raw))


def _extract_entitlements(
    application: Path,
) -> tuple[Mapping[str, Any], str, str]:
    codesign = _resolved_executable(
        "SIMS_IOS_NOTIFICATION_CODESIGN_EXECUTABLE",
        "codesign",
        "codesign",
    )
    result = run_process(
        [str(codesign), "-d", "--entitlements", ":-", str(application)],
        timeout_seconds=20,
        environment=_minimal_environment(),
    )
    if result.returncode != 0:
        raise AdapterBlocked("Runner entitlements could not be extracted")
    candidates = (result.stdout, result.stderr, result.stdout + result.stderr)
    entitlements: Mapping[str, Any] | None = None
    for candidate in candidates:
        start = candidate.find(b"<?xml")
        end = candidate.rfind(b"</plist>")
        if start >= 0 and end >= start:
            try:
                decoded = plistlib.loads(candidate[start : end + len(b"</plist>")])
            except plistlib.InvalidFileException:
                continue
            if isinstance(decoded, dict):
                entitlements = decoded
                break
    if entitlements is None:
        raise AdapterBlocked("Runner entitlements are not a readable plist")
    if entitlements.get("aps-environment") != EXPECTED_APNS_ENVIRONMENT:
        raise AdapterBlocked("Runner is not signed for development APNs")
    application_identifier = entitlements.get("application-identifier")
    team_identifier = entitlements.get("com.apple.developer.team-identifier")
    if (
        not isinstance(application_identifier, str)
        or not application_identifier.endswith(f".{BUNDLE_ID}")
        or not isinstance(team_identifier, str)
        or not application_identifier.startswith(f"{team_identifier}.")
        or _TEAM_ID.fullmatch(team_identifier) is None
    ):
        raise AdapterBlocked("Runner signing identity is not bound to the app bundle")
    with tempfile.TemporaryDirectory(prefix="sims-codesign-leaf-") as raw:
        work = Path(raw)
        work.chmod(0o700)
        prefix = work / "signing-leaf-"
        result = run_process(
            [
                str(codesign),
                "-d",
                f"--extract-certificates={prefix}",
                str(application),
            ],
            timeout_seconds=20,
            environment=_minimal_environment(),
        )
        leaf = Path(f"{prefix}0")
        if result.returncode != 0 or not leaf.is_file() or not leaf.stat().st_size:
            raise AdapterBlocked("Runner signing leaf certificate could not be extracted")
        leaf_sha = _sha256_file(leaf)
    return entitlements, team_identifier, leaf_sha


def _state_paths(args: argparse.Namespace) -> tuple[Path, Path, Path]:
    output = Path(args.output).expanduser().absolute()
    key = _sha256_text(f"{args.run_id}:{args.nonce}:{args.receiver}")[:24]
    state_directory = output.parent / f".ios-provider-state-{key}"
    _ensure_private_directory(state_directory)
    return (
        state_directory,
        state_directory / "payload.snapshot.json",
        state_directory / "lifecycle.json",
    )


_LIFECYCLE_STATES = {
    "fixture_spawn_pending",
    "accepted",
    "cleanup_spawn_pending",
    "cleaned",
    "rollback_spawn_pending",
    "recovered",
}


def _existing_lifecycle(
    lifecycle: Path,
    *,
    args: argparse.Namespace,
    request_sha: str,
    staging_sha: str,
) -> dict[str, Any] | None:
    if not lifecycle.exists():
        return None
    path = _private_regular_file(str(lifecycle), "provider lifecycle")
    value, _ = _read_json_object(path, "provider lifecycle")
    exact_keys = {
        "schema",
        "state",
        "runId",
        "nonce",
        "receiverDeviceIdSha256",
        "peerDeviceIdSha256",
        "requestSha256",
        "stagingManifestSha256",
        "apnsPayloadSha256",
        "receiverHandoffSha256",
        "stagedEnvelopeSha256",
        "recordedAt",
    }
    expected = {
        "schema": LIFECYCLE_SCHEMA,
        "runId": args.run_id,
        "nonce": args.nonce,
        "receiverDeviceIdSha256": _sha256_text(args.receiver),
        "peerDeviceIdSha256": _sha256_text(args.peer_device),
        "requestSha256": request_sha,
        "stagingManifestSha256": staging_sha,
    }
    if set(value) != exact_keys or any(
        value.get(key) != member for key, member in expected.items()
    ):
        raise AdapterBlocked("existing provider lifecycle binding is inconsistent")
    if value.get("state") not in _LIFECYCLE_STATES or any(
        _SHA256.fullmatch(str(value.get(key, ""))) is None
        for key in (
            "apnsPayloadSha256",
            "receiverHandoffSha256",
            "stagedEnvelopeSha256",
        )
    ):
        raise AdapterBlocked("existing provider lifecycle is invalid")
    _utc_timestamp(value.get("recordedAt"), "provider lifecycle recordedAt")
    return value


def _payload_source_bytes() -> bytes:
    payload_source = _private_regular_file(
        os.environ.get("SIMS_IOS_NOTIFICATION_APNS_PAYLOAD_PATH", "").strip(),
        "encrypted APNs payload",
    )
    try:
        payload_raw = payload_source.read_bytes()
    except OSError as error:
        raise AdapterBlocked("encrypted APNs payload is unreadable") from error
    return payload_raw


def _payload_binding(
    payload_raw: bytes,
    request: Mapping[str, Any],
) -> tuple[str, str]:
    if not payload_raw or len(payload_raw) > 4096:
        raise AdapterBlocked("actual APNs payload must contain at most 4096 bytes")
    payload = decode_json_object_bytes(payload_raw, "encrypted APNs payload")
    staged_sha = validate_apns_payload(payload, request, payload_raw)
    return _sha256_bytes(payload_raw), staged_sha


def _validate_common(args: argparse.Namespace) -> ProviderContext:
    required = (
        "scenario",
        "receiver",
        "peer_device",
        "application_binary",
        "provider_request",
        "staging_manifest",
        "relay_target",
        "relay_key",
        "run_id",
        "nonce",
    )
    if any(not isinstance(getattr(args, name, None), str) for name in required):
        raise AdapterBlocked("runtime provider arguments are incomplete")
    if any(not str(getattr(args, name)).strip() for name in required):
        raise AdapterBlocked("runtime provider arguments are incomplete")
    if args.scenario != SCENARIO:
        raise AdapterBlocked("unsupported provider scenario")
    if _RECEIVER_ID.fullmatch(args.receiver) is None:
        raise AdapterBlocked("receiver hardware identifier is invalid")
    if not is_transport_peer_id(args.peer_device):
        raise AdapterBlocked("peerDeviceId must be the receiver transport identity")
    if args.receiver == args.peer_device:
        raise AdapterBlocked("receiver hardware and transport identities must differ")
    for label, value in (("run id", args.run_id), ("nonce", args.nonce)):
        if _SAFE_TOKEN.fullmatch(value) is None:
            raise AdapterBlocked(f"{label} is invalid")
    if not args.relay_target or re.search(r"[\r\n]", args.relay_target):
        raise AdapterBlocked("relay target is invalid")

    application = Path(args.application_binary).expanduser().absolute()
    if not application.is_dir() or not application.name.endswith(".app"):
        raise AdapterBlocked("prebuilt Runner.app is unavailable")
    _private_regular_file(args.relay_key, "relay key")
    request_path = _private_regular_file(args.provider_request, "provider request")
    staging_path = _regular_file(args.staging_manifest, "staging manifest")
    request, request_raw = _read_json_object(request_path, "provider request")
    staging, staging_raw = _read_json_object(staging_path, "staging manifest")

    if request.get("schema") != PROVIDER_REQUEST_SCHEMA:
        raise AdapterBlocked("provider request schema is unsupported")
    request_keys = {
        "schema",
        "expectedTitle",
        "expectedBody",
        "expectedMessageText",
        "receiverDeviceId",
        "peerDeviceId",
    }
    if set(request) != request_keys:
        raise AdapterBlocked("provider request fields are not exact")
    for key, maximum in (
        ("expectedTitle", 30),
        ("expectedBody", 512),
        ("expectedMessageText", 140),
    ):
        if not _bounded_fixture_text(request.get(key), maximum=maximum):
            raise AdapterBlocked(f"provider request {key} is invalid")
    for key in ("receiverDeviceId", "peerDeviceId"):
        if not _bounded_string(request.get(key), maximum=512):
            raise AdapterBlocked(f"provider request {key} is invalid")
    message_text = str(request["expectedMessageText"])
    if message_text in str(request["expectedTitle"]) or message_text in str(
        request["expectedBody"]
    ):
        raise AdapterBlocked("provider request alert exposes expectedMessageText")
    if request.get("receiverDeviceId") != args.receiver or request.get(
        "peerDeviceId"
    ) != args.peer_device:
        raise AdapterBlocked("provider request is not bound to the exact receiver")

    exact_staging = {
        "schema": STAGING_SCHEMA,
        "environment": "staging",
        "provider": "apns",
        "providerConfigured": True,
        "providerCredentialsAvailable": True,
        "providerProbeSucceeded": True,
        "appSigningAvailable": True,
        "signingProbeSucceeded": True,
        "apnsEnvironment": EXPECTED_APNS_ENVIRONMENT,
        "signingEntitlementEnvironment": EXPECTED_APNS_ENVIRONMENT,
        "bundleId": BUNDLE_ID,
        "relayActive": True,
        "relayInboxSeedDriverAvailable": True,
        "dedicatedDisposableReceiver": True,
        "destructiveTestStateResetAuthorized": True,
        "providerCleanupAvailable": True,
        "productionDeploymentPerformed": False,
        "receiverDeviceId": args.receiver,
        "peerDeviceId": args.peer_device,
    }
    if any(staging.get(key) != value for key, value in exact_staging.items()):
        raise AdapterBlocked("staging manifest is not bound to development signing")
    if _secret_bearing_field(staging) is not None:
        raise AdapterBlocked("staging manifest contains a forbidden secret field")
    apns_host_for_manifest(staging)
    handoff = _validate_handoff(args)
    _, signing_team_id, signing_leaf_sha = _extract_entitlements(application)
    if (
        staging.get("signingIdentitySha256") != signing_leaf_sha
        or staging.get("signingCertificateSha256") != signing_leaf_sha
    ):
        raise AdapterBlocked(
            "Runner signing leaf certificate does not match the staging manifest"
        )
    for key in (
        "candidateRelaySha256",
        "provisioningProfileSha256",
        "relayFixtureDriverSha256",
        "payloadProducerSha256",
    ):
        if _SHA256.fullmatch(str(staging.get(key, ""))) is None:
            raise AdapterBlocked(f"staging manifest {key} is invalid")
    for key in ("candidateAppRevision", "candidateRelayRevision"):
        if not _bounded_string(staging.get(key), maximum=256):
            raise AdapterBlocked(f"staging manifest {key} is invalid")
    if _RELAY_REVISION.fullmatch(str(staging["candidateRelayRevision"])) is None:
        raise AdapterBlocked("staging manifest candidateRelayRevision is invalid")
    relay_addresses = staging.get("relayAddresses")
    if (
        not isinstance(relay_addresses, list)
        or not relay_addresses
        or any(not _bounded_string(address) for address in relay_addresses)
    ):
        raise AdapterBlocked("staging manifest relayAddresses is invalid")
    signing_expiry = _utc_timestamp(
        staging.get("signingExpiresAt"),
        "staging manifest signingExpiresAt",
    )
    if signing_expiry <= datetime.datetime.now(datetime.timezone.utc):
        raise AdapterBlocked("staging signing identity has expired")
    embedded_profile = _operator_regular_file(
        str(application / "embedded.mobileprovision"),
        "Runner embedded provisioning profile",
    )
    if _sha256_file(embedded_profile) != staging["provisioningProfileSha256"]:
        raise AdapterBlocked(
            "Runner embedded provisioning profile does not match staging"
        )
    fixture_driver = _fixture_driver()
    if _sha256_file(fixture_driver) != staging["relayFixtureDriverSha256"]:
        raise AdapterBlocked("relay fixture driver does not match staging")
    payload_producer = _executable(
        os.environ.get("SIMS_IOS_NOTIFICATION_PAYLOAD_PRODUCER", "").strip(),
        "iOS payload producer",
    )
    if _sha256_file(payload_producer) != staging["payloadProducerSha256"]:
        raise AdapterBlocked("iOS payload producer does not match staging")

    state_directory, payload_snapshot, lifecycle = _state_paths(args)
    request_sha = _sha256_bytes(request_raw)
    staging_sha = _sha256_bytes(staging_raw)
    bound = _existing_lifecycle(
        lifecycle,
        args=args,
        request_sha=request_sha,
        staging_sha=staging_sha,
    )
    if bound is not None and args.action == "setup":
        raise AdapterBlocked(
            "this run/nonce already has a lifecycle; use cleanup or rollback"
        )
    if args.action == "cleanup" and bound is None:
        raise AdapterBlocked("cleanup requires the setup lifecycle binding")

    if bound is not None and payload_snapshot.exists():
        snapshot = _private_regular_file(
            str(payload_snapshot),
            "bound encrypted APNs payload snapshot",
        )
        try:
            payload_raw = snapshot.read_bytes()
        except OSError as error:
            raise AdapterBlocked("bound encrypted APNs payload is unreadable") from error
        payload_sha, staged_sha = _payload_binding(payload_raw, request)
        if (
            payload_sha != bound["apnsPayloadSha256"]
            or staged_sha != bound["stagedEnvelopeSha256"]
        ):
            raise AdapterBlocked("bound encrypted APNs payload snapshot is inconsistent")
        handoff = ReceiverHandoff(handoff.value, str(bound["receiverHandoffSha256"]))
    else:
        payload_raw = _payload_source_bytes()
        payload_sha, staged_sha = _payload_binding(payload_raw, request)
        if bound is not None and (
            payload_sha != bound["apnsPayloadSha256"]
            or staged_sha != bound["stagedEnvelopeSha256"]
        ):
            raise AdapterBlocked(
                "current encrypted APNs payload conflicts with the journaled run"
            )
        if bound is not None:
            handoff = ReceiverHandoff(
                handoff.value,
                str(bound["receiverHandoffSha256"]),
            )
        _write_bytes_private(payload_snapshot, payload_raw, mode=0o400)
    if _sha256_file(payload_snapshot) != payload_sha:
        raise AdapterFailure("private APNs payload snapshot changed during creation")
    return ProviderContext(
        args=args,
        request=request,
        staging=staging,
        handoff=handoff,
        signing_team_id=signing_team_id,
        request_sha=request_sha,
        staging_sha=staging_sha,
        payload_sha=payload_sha,
        staged_sha=staged_sha,
        state_directory=state_directory,
        payload_snapshot=payload_snapshot,
        lifecycle=lifecycle,
        initial_lifecycle_state=(str(bound["state"]) if bound is not None else None),
    )


def _lifecycle_value(context: ProviderContext, state: str) -> dict[str, Any]:
    return {
        "schema": LIFECYCLE_SCHEMA,
        "state": state,
        "runId": context.args.run_id,
        "nonce": context.args.nonce,
        "receiverDeviceIdSha256": _sha256_text(context.args.receiver),
        "peerDeviceIdSha256": _sha256_text(context.args.peer_device),
        "requestSha256": context.request_sha,
        "stagingManifestSha256": context.staging_sha,
        "apnsPayloadSha256": context.payload_sha,
        "receiverHandoffSha256": context.handoff.digest,
        "stagedEnvelopeSha256": context.staged_sha,
        "recordedAt": _utc_now(),
    }


def _write_lifecycle(context: ProviderContext, state: str) -> None:
    _write_json_private(context.lifecycle, _lifecycle_value(context, state))


def _read_der_length(value: bytes, offset: int) -> tuple[int, int]:
    if offset >= len(value):
        raise AdapterFailure("provider signature is malformed")
    first = value[offset]
    if first < 0x80:
        return first, offset + 1
    width = first & 0x7F
    if width == 0 or width > 2 or offset + 1 + width > len(value):
        raise AdapterFailure("provider signature is malformed")
    return int.from_bytes(value[offset + 1 : offset + 1 + width], "big"), offset + 1 + width


def _der_es256_to_raw(value: bytes) -> bytes:
    if not value or value[0] != 0x30:
        raise AdapterFailure("provider signature is malformed")
    sequence_length, offset = _read_der_length(value, 1)
    if offset + sequence_length != len(value):
        raise AdapterFailure("provider signature is malformed")
    integers: list[bytes] = []
    for _ in range(2):
        if offset >= len(value) or value[offset] != 0x02:
            raise AdapterFailure("provider signature is malformed")
        length, start = _read_der_length(value, offset + 1)
        integer = value[start : start + length].lstrip(b"\x00")
        offset = start + length
        if not integer or len(integer) > 32:
            raise AdapterFailure("provider signature is malformed")
        integers.append(integer.rjust(32, b"\x00"))
    if offset != len(value):
        raise AdapterFailure("provider signature is malformed")
    return b"".join(integers)


def _base64_url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _prepare_apns_credentials(context: ProviderContext) -> tuple[Path, str, Path]:
    auth_key = _private_regular_file(
        os.environ.get("SIMS_IOS_APNS_AUTH_KEY_PATH", "").strip(),
        "APNs auth key",
    )
    key_id = os.environ.get("SIMS_IOS_APNS_KEY_ID", "").strip()
    team_id = os.environ.get("SIMS_IOS_APNS_TEAM_ID", "").strip()
    if _KEY_ID.fullmatch(key_id) is None or _TEAM_ID.fullmatch(team_id) is None:
        raise AdapterBlocked("APNs key ID and team ID are unavailable or invalid")
    if team_id != context.signing_team_id:
        raise AdapterBlocked("APNs team ID does not match Runner entitlements")
    curl = _resolved_executable(
        "SIMS_IOS_NOTIFICATION_CURL_EXECUTABLE",
        "curl",
        "curl",
    )
    return auth_key, key_id, curl


def _mint_apns_jwt(auth_key: Path, key_id: str, team_id: str) -> str:
    openssl = _resolved_executable(
        "SIMS_IOS_NOTIFICATION_OPENSSL_EXECUTABLE",
        "openssl",
        "OpenSSL",
    )
    now = int(datetime.datetime.now(datetime.timezone.utc).timestamp())
    header = _base64_url(
        json.dumps(
            {"alg": "ES256", "kid": key_id},
            separators=(",", ":"),
            sort_keys=True,
        ).encode("utf-8")
    )
    claims = _base64_url(
        json.dumps(
            {"iat": now, "iss": team_id},
            separators=(",", ":"),
            sort_keys=True,
        ).encode("utf-8")
    )
    signing_input = f"{header}.{claims}".encode("ascii")
    with tempfile.TemporaryDirectory(prefix="sims-apns-sign-") as raw:
        work = Path(raw)
        work.chmod(0o700)
        payload = work / "jwt-input"
        signature = work / "jwt-signature.der"
        _write_bytes_private(payload, signing_input)
        result = run_process(
            [
                str(openssl),
                "dgst",
                "-sha256",
                "-sign",
                str(auth_key),
                "-out",
                str(signature),
                str(payload),
            ],
            timeout_seconds=20,
            environment=_minimal_environment(),
        )
        if result.returncode != 0 or not signature.is_file():
            raise AdapterBlocked("APNs signing key could not mint an ES256 token")
        raw_signature = _der_es256_to_raw(signature.read_bytes())
    return f"{header}.{claims}.{_base64_url(raw_signature)}"


def _profile_utc(value: object, label: str) -> datetime.datetime:
    if not isinstance(value, datetime.datetime):
        raise AdapterBlocked(f"provisioning profile {label} is unavailable")
    if value.tzinfo is None:
        return value.replace(tzinfo=datetime.timezone.utc)
    return value.astimezone(datetime.timezone.utc)


def _profile_timestamp(value: datetime.datetime) -> str:
    return (
        value.astimezone(datetime.timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z")
    )


def _probe_value(args: argparse.Namespace, name: str, label: str) -> str:
    value = str(getattr(args, name, "") or "").strip()
    if not value:
        raise AdapterBlocked(f"{label} is required for the local staging probe")
    return value


def _decode_provisioning_profile(profile: Path) -> dict[str, Any]:
    security = _resolved_executable(
        "SIMS_IOS_NOTIFICATION_SECURITY_EXECUTABLE",
        "security",
        "macOS security tool",
    )
    result = run_process(
        [str(security), "cms", "-D", "-i", str(profile)],
        timeout_seconds=30,
        environment=_minimal_environment(),
    )
    if result.returncode != 0:
        raise AdapterBlocked("development provisioning profile CMS is invalid")
    try:
        decoded = plistlib.loads(result.stdout)
    except (ValueError, plistlib.InvalidFileException) as error:
        raise AdapterBlocked("development provisioning profile is not a plist") from error
    if not isinstance(decoded, dict):
        raise AdapterBlocked("development provisioning profile is not a dictionary")
    return decoded


def _require_go125_binary(executable: Path) -> None:
    go = _resolved_executable(
        "SIMS_IOS_NOTIFICATION_GO_EXECUTABLE",
        "go",
        "Go tool",
    )
    result = run_process(
        [str(go), "version", "-m", str(executable)],
        timeout_seconds=20,
        environment=_minimal_environment({"GOTOOLCHAIN": "local"}),
    )
    build_info = (result.stdout + b"\n" + result.stderr).decode(
        "utf-8", errors="replace"
    )
    if result.returncode != 0 or re.search(r"\bgo1\.25(?:\.[0-9]+)?\b", build_info) is None:
        raise AdapterBlocked("payload producer is not a prebuilt Go 1.25 binary")


def _probe(args: argparse.Namespace) -> None:
    receiver = _probe_value(args, "receiver", "receiver device ID")
    peer_device = _probe_value(args, "peer_device", "receiver peer ID")
    if _RECEIVER_ID.fullmatch(receiver) is None or not is_transport_peer_id(
        peer_device
    ):
        raise AdapterBlocked("local probe receiver binding is invalid")
    if receiver == peer_device:
        raise AdapterBlocked("local probe hardware and transport identities must differ")

    profile_raw = (
        str(args.provisioning_profile or "").strip()
        or os.environ.get("SIMS_IOS_PROVISIONING_PROFILE_PATH", "").strip()
    )
    profile = _operator_regular_file(profile_raw, "development provisioning profile")
    fixture_raw = (
        str(args.relay_fixture_driver or "").strip()
        or os.environ.get(
            "SIMS_IOS_NOTIFICATION_RELAY_FIXTURE_DRIVER", ""
        ).strip()
    )
    fixture_driver = _executable(fixture_raw, "relay fixture driver")
    producer_raw = (
        str(args.payload_producer or "").strip()
        or os.environ.get("SIMS_IOS_NOTIFICATION_PAYLOAD_PRODUCER", "").strip()
    )
    payload_producer = _executable(producer_raw, "iOS payload producer")
    _require_go125_binary(payload_producer)
    candidate_app_revision = _probe_value(
        args, "candidate_app_revision", "candidate app revision"
    )
    candidate_relay_revision = _probe_value(
        args, "candidate_relay_revision", "candidate relay revision"
    )
    candidate_relay_sha = _probe_value(
        args, "candidate_relay_sha256", "candidate relay SHA-256"
    )
    if (
        not _bounded_string(candidate_app_revision, maximum=256)
        or _RELAY_REVISION.fullmatch(candidate_relay_revision) is None
        or _SHA256.fullmatch(candidate_relay_sha) is None
    ):
        raise AdapterBlocked("local probe candidate revision binding is invalid")
    relay_addresses = sorted(set(args.relay_address or []))
    if (
        not relay_addresses
        or any(
            not _bounded_string(address)
            or re.fullmatch(r"[A-Za-z0-9./_:@+\[\]-]{3,512}", address) is None
            for address in relay_addresses
        )
    ):
        raise AdapterBlocked("local probe relay addresses are invalid")

    decoded = _decode_provisioning_profile(profile)
    team_id = os.environ.get("SIMS_IOS_APNS_TEAM_ID", "").strip()
    key_id = os.environ.get("SIMS_IOS_APNS_KEY_ID", "").strip()
    if _TEAM_ID.fullmatch(team_id) is None or _KEY_ID.fullmatch(key_id) is None:
        raise AdapterBlocked("APNs key ID and team ID are unavailable or invalid")
    team_identifiers = decoded.get("TeamIdentifier")
    entitlements = decoded.get("Entitlements")
    provisioned_devices = decoded.get("ProvisionedDevices")
    certificates = decoded.get("DeveloperCertificates")
    if (
        not isinstance(team_identifiers, list)
        or team_identifiers != [team_id]
        or not isinstance(entitlements, dict)
        or entitlements.get("application-identifier")
        != f"{team_id}.{BUNDLE_ID}"
        or entitlements.get("com.apple.developer.team-identifier") != team_id
        or entitlements.get("aps-environment") != EXPECTED_APNS_ENVIRONMENT
        or not isinstance(provisioned_devices, list)
        or receiver not in provisioned_devices
        or not isinstance(certificates, list)
        or len(certificates) != 1
        or not isinstance(certificates[0], bytes)
        or not certificates[0]
    ):
        raise AdapterBlocked(
            "provisioning profile is not the exact development receiver profile"
        )
    expires = _profile_utc(decoded.get("ExpirationDate"), "expiration")
    if expires <= datetime.datetime.now(datetime.timezone.utc):
        raise AdapterBlocked("development provisioning profile has expired")
    leaf_sha = _sha256_bytes(certificates[0])

    auth_key = _private_regular_file(
        os.environ.get("SIMS_IOS_APNS_AUTH_KEY_PATH", "").strip(),
        "APNs auth key",
    )
    # A local ES256 signing operation proves that the private key is parseable
    # and matches the APNs JWT algorithm without contacting Apple.
    jwt = _mint_apns_jwt(auth_key, key_id, team_id)
    if len(jwt.split(".")) != 3:
        raise AdapterBlocked("APNs auth key did not produce a valid local JWT")

    manifest: dict[str, Any] = {
        "schema": STAGING_SCHEMA,
        "environment": "staging",
        "provider": "apns",
        "providerConfigured": True,
        "providerCredentialsAvailable": True,
        "providerProbeSucceeded": True,
        "appSigningAvailable": True,
        "signingProbeSucceeded": True,
        "apnsEnvironment": EXPECTED_APNS_ENVIRONMENT,
        "signingEntitlementEnvironment": EXPECTED_APNS_ENVIRONMENT,
        "bundleId": BUNDLE_ID,
        "relayActive": True,
        "relayInboxSeedDriverAvailable": True,
        "dedicatedDisposableReceiver": True,
        "destructiveTestStateResetAuthorized": True,
        "providerCleanupAvailable": True,
        "productionDeploymentPerformed": False,
        "candidateAppRevision": candidate_app_revision,
        "candidateRelayRevision": candidate_relay_revision,
        "candidateRelaySha256": candidate_relay_sha,
        "signingIdentitySha256": leaf_sha,
        "signingCertificateSha256": leaf_sha,
        "provisioningProfileSha256": _sha256_file(profile),
        "relayFixtureDriverSha256": _sha256_file(fixture_driver),
        "payloadProducerSha256": _sha256_file(payload_producer),
        "signingExpiresAt": _profile_timestamp(expires),
        "receiverDeviceId": receiver,
        "peerDeviceId": peer_device,
        "relayAddresses": relay_addresses,
    }
    if _secret_bearing_field(manifest) is not None:
        raise AdapterFailure("generated staging manifest contains a secret field")
    _write_json_private(Path(args.output).expanduser().absolute(), manifest)


def _curl_quote(value: str) -> str:
    if "\n" in value or "\r" in value:
        raise AdapterBlocked("provider input contains a line break")
    return value.replace("\\", "\\\\").replace('"', '\\"')


def raise_for_apns_failure(status: str, reason: object) -> NoReturn:
    reason_value = reason if isinstance(reason, str) else None
    if reason_value in _APNS_CREDENTIAL_REASONS:
        raise AdapterBlocked("APNs provider credentials do not match the signed app")
    if reason_value in _APNS_HANDOFF_REASONS:
        raise AdapterBlocked("receiver APNs handoff is stale or bound to another topic")
    detail = reason_value if reason_value else "missing structured APNs reason"
    raise AdapterFailure(f"APNs rejected the request: {detail} (HTTP {status})")


def _submit_apns(
    context: ProviderContext,
    *,
    curl: Path,
    jwt: str,
) -> tuple[str, str]:
    if _sha256_file(context.payload_snapshot) != context.payload_sha:
        raise AdapterFailure("private APNs payload snapshot changed before submission")
    host = apns_host_for_manifest(context.staging)
    with tempfile.TemporaryDirectory(prefix="sims-apns-submit-") as raw:
        work = Path(raw)
        work.chmod(0o700)
        config = work / "curl.conf"
        headers = work / "response.headers"
        body = work / "response.body"
        expiration = (
            int(datetime.datetime.now(datetime.timezone.utc).timestamp())
            + APNS_DELIVERY_WINDOW_SECONDS
        )
        config_value = "\n".join(
            [
                "http2",
                "silent",
                "show-error",
                'request = "POST"',
                f'url = "{_curl_quote(host + "/3/device/" + context.handoff.device_token)}"',
                f'header = "{_curl_quote("authorization: bearer " + jwt)}"',
                f'header = "{_curl_quote("apns-topic: " + BUNDLE_ID)}"',
                'header = "apns-push-type: alert"',
                'header = "apns-priority: 10"',
                f'header = "apns-expiration: {expiration}"',
                f'data-binary = "@{_curl_quote(str(context.payload_snapshot))}"',
                f'dump-header = "{_curl_quote(str(headers))}"',
                f'output = "{_curl_quote(str(body))}"',
                'write-out = "%{http_code}"',
                "",
            ]
        ).encode("utf-8")
        _write_bytes_private(config, config_value)
        result = run_process(
            [str(curl), "--disable", "--config", str(config)],
            timeout_seconds=_timeout_seconds(
                "SIMS_IOS_NOTIFICATION_APNS_TIMEOUT_SECONDS",
                60,
                120,
            ),
            environment=_minimal_environment(),
        )
        if result.returncode != 0:
            raise AdapterFailure("APNs submission command failed")
        status = result.stdout.decode("ascii", errors="replace").strip()
        response: Mapping[str, Any] = {}
        if body.is_file() and body.stat().st_size:
            try:
                response = decode_json_object_bytes(body.read_bytes(), "APNs response")
            except AdapterBlocked:
                response = {}
        if status != "200":
            raise_for_apns_failure(status, response.get("reason"))
        if not headers.is_file():
            raise AdapterFailure("APNs response omitted headers")
        match = re.search(
            r"^apns-id:\s*([^\s]+)\s*$",
            headers.read_text(encoding="utf-8", errors="replace"),
            re.IGNORECASE | re.MULTILINE,
        )
        if match is None:
            raise AdapterFailure("APNs response omitted its message ID")
    if _sha256_file(context.payload_snapshot) != context.payload_sha:
        raise AdapterFailure("private APNs payload snapshot changed during submission")
    return match.group(1), _utc_now()


def _fixture_driver() -> Path:
    return _executable(
        os.environ.get("SIMS_IOS_NOTIFICATION_RELAY_FIXTURE_DRIVER", "").strip(),
        "relay fixture driver",
    )


def _fixture_command(
    context: ProviderContext,
    *,
    action: str,
    output: Path,
    provider_receipt: Path | None = None,
) -> list[str]:
    args = context.args
    command = [
        str(_fixture_driver()),
        "--action",
        action,
        "--scenario",
        args.scenario,
        "--receiver",
        args.receiver,
        "--peer-device",
        args.peer_device,
        "--provider-request",
        str(Path(args.provider_request).absolute()),
        "--staging-manifest",
        str(Path(args.staging_manifest).absolute()),
        "--relay-target",
        args.relay_target,
        "--relay-key",
        str(Path(args.relay_key).absolute()),
        "--run-id",
        args.run_id,
        "--nonce",
        args.nonce,
        "--apns-payload",
        str(context.payload_snapshot),
        "--apns-payload-sha256",
        context.payload_sha,
        "--receiver-handoff-sha256",
        context.handoff.digest,
        "--lifecycle",
        str(context.lifecycle),
    ]
    if provider_receipt is not None:
        command.extend(["--provider-receipt", str(provider_receipt)])
    command.extend(["--output", str(output)])
    return command


def _run_fixture_driver(
    context: ProviderContext,
    *,
    action: str,
    provider_receipt: Path | None = None,
) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="sims-relay-fixture-") as raw:
        work = Path(raw)
        work.chmod(0o700)
        output = work / "receipt.json"
        result = run_process(
            _fixture_command(
                context,
                action=action,
                output=output,
                provider_receipt=provider_receipt,
            ),
            timeout_seconds=_timeout_seconds(
                "SIMS_IOS_NOTIFICATION_FIXTURE_TIMEOUT_SECONDS",
                120,
                240,
            ),
            environment=_minimal_environment(
                {
                    "SIMS_CHILD_BUILDS_FORBIDDEN": "1",
                    "SIMS_MANUAL_ACTIONS_FORBIDDEN": "1",
                    "SIMS_PREBUILT_APPLICATION_BINARY": str(
                        Path(context.args.application_binary).absolute()
                    ),
                }
            ),
        )
        if result.returncode != 0 or not output.is_file():
            raise AdapterFailure("relay fixture action did not produce a receipt")
        receipt, _ = _read_json_object(output, "relay fixture receipt")
    return receipt


def _validate_fixture_receipt(
    receipt: Mapping[str, Any],
    context: ProviderContext,
    *,
    action: str,
    provider_receipt_sha: str | None = None,
) -> None:
    if _secret_bearing_field(receipt) is not None:
        raise AdapterFailure("relay fixture receipt contains forbidden secret material")
    args = context.args
    exact: dict[str, Any] = {
        "schema": RELAY_FIXTURE_RECEIPT_SCHEMA,
        "action": action,
        "runId": args.run_id,
        "nonce": args.nonce,
        "receiverDeviceIdSha256": _sha256_text(args.receiver),
        "peerDeviceIdSha256": _sha256_text(args.peer_device),
        "requestSha256": context.request_sha,
        "apnsPayloadSha256": context.payload_sha,
        "receiverHandoffSha256": context.handoff.digest,
        "childBuildCount": 0,
        "manualActionCount": 0,
    }
    if action == "setup":
        exact.update(
            {
                "status": "seeded",
                "relayInboxSeeded": True,
                "stagedEnvelopeSha256": context.staged_sha,
            }
        )
    elif action == "cleanup":
        exact.update(
            {
                "status": "cleared",
                "relayFixtureCleared": True,
                "providerReceiptSha256": provider_receipt_sha,
            }
        )
    elif action == "rollback":
        exact.update(
            {
                "status": "cleared",
                "relayFixtureCleared": True,
                "stagedEnvelopeSha256": context.staged_sha,
            }
        )
    else:
        raise AdapterFailure("relay fixture receipt action is unsupported")
    if any(receipt.get(key) != value for key, value in exact.items()):
        raise AdapterFailure("relay fixture receipt is not bound to the exact action")


def _write_relay_log(context: ProviderContext, output: Path) -> tuple[str, str]:
    args = context.args
    name = f"relay-{_sha256_text(args.run_id + ':' + args.nonce)[:16]}.redacted.log"
    path = output.parent / name
    _write_json_private(
        path,
        {
            "schema": "mknoon.sims.ios-payload-relay-redacted-log.v1",
            "status": "seeded",
            "runIdSha256": _sha256_text(args.run_id),
            "nonceSha256": _sha256_text(args.nonce),
            "receiverDeviceIdSha256": _sha256_text(args.receiver),
            "peerDeviceIdSha256": _sha256_text(args.peer_device),
            "requestSha256": context.request_sha,
            "apnsPayloadSha256": context.payload_sha,
            "receiverHandoffSha256": context.handoff.digest,
            "stagedEnvelopeSha256": context.staged_sha,
            "childBuildCount": 0,
            "manualActionCount": 0,
        },
    )
    return name, _sha256_file(path)


def _sender_projection_driver() -> Path:
    configured = os.environ.get(
        "SIMS_IOS_NOTIFICATION_RECEIVER_BOOTSTRAP_DRIVER", ""
    ).strip()
    if configured:
        return _executable(configured, "receiver bootstrap driver")
    return _executable(
        str(Path(__file__).with_name("ios_receiver_bootstrap.py")),
        "receiver bootstrap driver",
    )


def _cleanup_sender_projection(context: ProviderContext) -> None:
    driver = _sender_projection_driver()
    receipt_path = context.state_directory / "sender-projection-cleanup.json"
    try:
        receipt_path.unlink(missing_ok=True)
    except OSError as error:
        raise AdapterFailure("sender projection cleanup receipt is unavailable") from error
    environment = _minimal_environment(
        {
            "SIMS_CHILD_BUILDS_FORBIDDEN": "1",
            "SIMS_MANUAL_ACTIONS_FORBIDDEN": "1",
            "SIMS_IOS_PHYSICAL_DEVICE_ID": context.args.receiver,
            "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE": str(
                context.handoff.value["captureNonce"]
            ),
            "SIMS_IOS_NOTIFICATION_APNS_PAYLOAD_PATH": str(
                context.payload_snapshot
            ),
            "SIMS_IOS_NOTIFICATION_SENDER_PROJECTION_RECEIPT_PATH": str(
                receipt_path
            ),
        }
    )
    result = run_process(
        [str(driver), "--action", "cleanup-sender"],
        timeout_seconds=_timeout_seconds(
            "SIMS_IOS_NOTIFICATION_DEVICE_TIMEOUT_SECONDS",
            120,
            180,
        ),
        environment=environment,
    )
    if result.returncode != 0:
        raise AdapterFailure("private sender projection cleanup failed")
    receipt_file = _private_regular_file(
        str(receipt_path),
        "sender projection cleanup receipt",
    )
    receipt, _ = _read_json_object(
        receipt_file,
        "sender projection cleanup receipt",
    )
    payload = decode_json_object_bytes(
        context.payload_snapshot.read_bytes(),
        "bound encrypted APNs payload",
    )
    sender_peer_id = str(payload.get("sender_id", ""))
    expected = {
        "schema": "mknoon.sims.ios-sender-projection-host-receipt.v1",
        "action": "cleanup-sender",
        "status": "PASS",
        "containsSecrets": False,
        "bundleId": BUNDLE_ID,
        "captureNonceSha256": _sha256_text(
            str(context.handoff.value["captureNonce"])
        ),
        "receiverDeviceIdSha256": _sha256_text(context.args.receiver),
        "senderPeerIdSha256": _sha256_text(sender_peer_id),
        "apnsPayloadSha256": context.payload_sha,
        "nativeStatus": "cleaned",
    }
    exact_keys = {
        *expected.keys(),
        "fixtureDigest",
        "resultCode",
        "completedAt",
    }
    if (
        set(receipt) != exact_keys
        or any(receipt.get(key) != value for key, value in expected.items())
        or _SHA256.fullmatch(str(receipt.get("fixtureDigest", ""))) is None
        or receipt.get("resultCode") not in {"ok", "idempotent"}
    ):
        raise AdapterFailure("sender projection cleanup receipt is not bound")
    _utc_timestamp(
        receipt.get("completedAt"),
        "sender projection cleanup completedAt",
    )


def _remove_candidate_application(context: ProviderContext) -> None:
    xcrun = _resolved_executable(
        "SIMS_IOS_NOTIFICATION_XCRUN_EXECUTABLE",
        "xcrun",
        "xcrun",
    )
    with tempfile.TemporaryDirectory(prefix="sims-ios-uninstall-") as raw:
        work = Path(raw)
        work.chmod(0o700)
        result_json = work / "result.json"
        command_log = work / "command.log"
        result = run_process(
            [
                str(xcrun),
                "devicectl",
                "device",
                "uninstall",
                "app",
                "--device",
                context.args.receiver,
                BUNDLE_ID,
                "--json-output",
                str(result_json),
                "--log-output",
                str(command_log),
                "--quiet",
            ],
            timeout_seconds=_timeout_seconds(
                "SIMS_IOS_NOTIFICATION_DEVICE_TIMEOUT_SECONDS",
                60,
                120,
            ),
            environment=_minimal_environment(),
        )
        combined = (result.stdout + b"\n" + result.stderr).decode(
            "utf-8", errors="replace"
        ).lower()
        already_absent = any(
            marker in combined
            for marker in (
                "not installed",
                "application not found",
                "no matching application",
            )
        )
        if result.returncode != 0 and not already_absent:
            raise AdapterFailure("authorized candidate-app removal failed")
        if result.returncode == 0 and not result_json.is_file():
            raise AdapterFailure("candidate-app removal omitted its result")


def _remove_payload_snapshot(context: ProviderContext) -> None:
    try:
        context.payload_snapshot.unlink(missing_ok=True)
    except OSError as error:
        raise AdapterFailure(
            "private APNs payload snapshot could not be removed"
        ) from error
    if context.payload_snapshot.exists():
        raise AdapterFailure("private APNs payload snapshot remained after cleanup")


def _perform_recovery(context: ProviderContext) -> list[str]:
    failures: list[str] = []
    try:
        _write_lifecycle(context, "rollback_spawn_pending")
    except Exception:
        # Mutation may already exist. Journal failure must not suppress cleanup.
        pass
    try:
        receipt = _run_fixture_driver(context, action="rollback")
        _validate_fixture_receipt(receipt, context, action="rollback")
    except Exception:
        failures.append("relay fixture rollback")
    if context.initial_lifecycle_state not in {"recovered", "cleaned"}:
        try:
            _cleanup_sender_projection(context)
        except Exception:
            failures.append("sender projection cleanup")
    try:
        _remove_candidate_application(context)
    except Exception:
        failures.append("candidate-app removal")
    if not failures:
        try:
            _remove_payload_snapshot(context)
        except Exception:
            failures.append("payload snapshot removal")
    if not failures:
        try:
            _write_lifecycle(context, "recovered")
        except Exception:
            failures.append("recovery lifecycle journal")
    return failures


def _provider_receipt(
    context: ProviderContext,
    *,
    provider_id: str,
    accepted_at: str,
    relay_log_name: str,
    relay_log_sha: str,
) -> dict[str, Any]:
    args = context.args
    return {
        "schema": PROVIDER_RECEIPT_SCHEMA,
        "status": "accepted",
        "provider": "apns",
        "relayInboxSeeded": True,
        "providerAccepted": True,
        "appSetupAutomated": True,
        "dedicatedDisposableReceiver": True,
        "cleanupDriverAvailable": True,
        "childBuildCount": 0,
        "manualActionCount": 0,
        "runId": args.run_id,
        "nonce": args.nonce,
        "receiverDeviceIdSha256": _sha256_text(args.receiver),
        "requestSha256": context.request_sha,
        "apnsPayloadSha256": context.payload_sha,
        "receiverHandoffSha256": context.handoff.digest,
        "providerMessageIdSha256": _sha256_text(provider_id),
        "relayLogPath": relay_log_name,
        "relayLogSha256": relay_log_sha,
        "stagedEnvelopeSha256": context.staged_sha,
        "acceptedAt": accepted_at,
    }


def _setup(context: ProviderContext) -> None:
    auth_key, key_id, curl = _prepare_apns_credentials(context)
    jwt = _mint_apns_jwt(auth_key, key_id, context.signing_team_id)
    output = Path(context.args.output).expanduser().absolute()
    _write_lifecycle(context, "fixture_spawn_pending")
    try:
        fixture_receipt = _run_fixture_driver(context, action="setup")
        _validate_fixture_receipt(fixture_receipt, context, action="setup")
        if _sha256_file(context.payload_snapshot) != context.payload_sha:
            raise AdapterFailure("relay fixture changed the private payload snapshot")
        provider_id, accepted_at = _submit_apns(context, curl=curl, jwt=jwt)
        relay_log_name, relay_log_sha = _write_relay_log(context, output)
        receipt = _provider_receipt(
            context,
            provider_id=provider_id,
            accepted_at=accepted_at,
            relay_log_name=relay_log_name,
            relay_log_sha=relay_log_sha,
        )
        if _secret_bearing_field(receipt) is not None:
            raise AdapterFailure("generated provider receipt contains a secret field")
        _write_json_private(output, receipt)
        _write_lifecycle(context, "accepted")
    except Exception:
        failures = _perform_recovery(context)
        if failures:
            raise AdapterFailure(
                "provider setup failed and automated rollback was incomplete: "
                + ", ".join(failures)
            )
        raise


def _cleanup_receipt(
    context: ProviderContext,
    provider_receipt_sha: str,
) -> dict[str, Any]:
    args = context.args
    return {
        "schema": CLEANUP_RECEIPT_SCHEMA,
        "status": "cleaned",
        "dedicatedDisposableReceiver": True,
        "relayFixtureCleared": True,
        "appTestStateCleared": True,
        "notificationStateCleared": True,
        "candidateAppRemoved": True,
        "childBuildCount": 0,
        "manualActionCount": 0,
        "runId": args.run_id,
        "nonce": args.nonce,
        "receiverDeviceIdSha256": _sha256_text(args.receiver),
        "providerReceiptSha256": provider_receipt_sha,
        "apnsPayloadSha256": context.payload_sha,
        "receiverHandoffSha256": context.handoff.digest,
        "cleanedAt": _utc_now(),
    }


def _cleanup(context: ProviderContext) -> None:
    args = context.args
    if not args.provider_receipt:
        raise AdapterBlocked("cleanup requires the exact provider receipt")
    provider_receipt_path = _private_regular_file(
        args.provider_receipt,
        "provider receipt",
    )
    provider_receipt, _ = _read_json_object(provider_receipt_path, "provider receipt")
    expected = {
        "schema": PROVIDER_RECEIPT_SCHEMA,
        "status": "accepted",
        "runId": args.run_id,
        "nonce": args.nonce,
        "receiverDeviceIdSha256": _sha256_text(args.receiver),
        "requestSha256": context.request_sha,
        "apnsPayloadSha256": context.payload_sha,
        "receiverHandoffSha256": context.handoff.digest,
    }
    if any(provider_receipt.get(key) != value for key, value in expected.items()):
        raise AdapterBlocked("provider receipt is not bound to this cleanup")
    provider_receipt_sha = _sha256_file(provider_receipt_path)
    _write_lifecycle(context, "cleanup_spawn_pending")
    try:
        fixture_receipt = _run_fixture_driver(
            context,
            action="cleanup",
            provider_receipt=provider_receipt_path,
        )
        _validate_fixture_receipt(
            fixture_receipt,
            context,
            action="cleanup",
            provider_receipt_sha=provider_receipt_sha,
        )
        _cleanup_sender_projection(context)
        _remove_candidate_application(context)
        _remove_payload_snapshot(context)
        _write_lifecycle(context, "cleaned")
        receipt = _cleanup_receipt(context, provider_receipt_sha)
        _write_json_private(Path(args.output).expanduser().absolute(), receipt)
    except Exception:
        failures = _perform_recovery(context)
        if failures:
            raise AdapterFailure(
                "provider cleanup and recovery were incomplete: " + ", ".join(failures)
            )
        raise


def _rollback(context: ProviderContext) -> None:
    failures = _perform_recovery(context)
    if failures:
        raise AdapterFailure("provider rollback was incomplete: " + ", ".join(failures))
    args = context.args
    receipt = {
        "schema": RECOVERY_RECEIPT_SCHEMA,
        "status": "recovered",
        "relayFixtureCleared": True,
        "candidateAppRemoved": True,
        "childBuildCount": 0,
        "manualActionCount": 0,
        "runId": args.run_id,
        "nonce": args.nonce,
        "receiverDeviceIdSha256": _sha256_text(args.receiver),
        "requestSha256": context.request_sha,
        "apnsPayloadSha256": context.payload_sha,
        "receiverHandoffSha256": context.handoff.digest,
        "recoveredAt": _utc_now(),
    }
    _write_json_private(Path(args.output).expanduser().absolute(), receipt)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Seed one exact encrypted relay fixture, submit the same bytes to "
            "development APNs, and idempotently clean the authorized receiver."
        )
    )
    parser.add_argument(
        "--action",
        required=True,
        choices=("probe", "setup", "cleanup", "rollback"),
    )
    parser.add_argument("--scenario")
    parser.add_argument("--receiver")
    parser.add_argument("--peer-device")
    parser.add_argument("--application-binary")
    parser.add_argument("--provider-request")
    parser.add_argument("--staging-manifest")
    parser.add_argument("--relay-target")
    parser.add_argument("--relay-key")
    parser.add_argument("--run-id")
    parser.add_argument("--nonce")
    parser.add_argument("--provider-receipt")
    parser.add_argument("--provisioning-profile")
    parser.add_argument("--candidate-app-revision")
    parser.add_argument("--candidate-relay-revision")
    parser.add_argument("--candidate-relay-sha256")
    parser.add_argument("--relay-address", action="append")
    parser.add_argument("--relay-fixture-driver")
    parser.add_argument("--payload-producer")
    parser.add_argument("--output", required=True)
    return parser


def _signal_handler(signum: int, _frame: object) -> NoReturn:
    raise AdapterInterrupted(f"received signal {signum}")


def _exit_blocked(detail: str) -> NoReturn:
    print(f"iOS provider adapter blocked: {detail}", file=sys.stderr)
    raise SystemExit(78)


def _exit_failed(detail: str) -> NoReturn:
    print(f"iOS provider adapter failed: {detail}", file=sys.stderr)
    raise SystemExit(1)


def main(argv: list[str] | None = None) -> int:
    signal.signal(signal.SIGTERM, _signal_handler)
    signal.signal(signal.SIGINT, _signal_handler)
    args = _parser().parse_args(argv)
    try:
        if args.action == "probe":
            _probe(args)
            return 0
        context = _validate_common(args)
        if args.action == "setup":
            _setup(context)
        elif args.action == "cleanup":
            _cleanup(context)
        else:
            _rollback(context)
    except AdapterBlocked as error:
        _exit_blocked(str(error))
    except (AdapterFailure, OSError) as error:
        detail = str(error) if isinstance(error, AdapterFailure) else "private I/O failed"
        _exit_failed(detail)
    except Exception:
        _exit_failed("unexpected typed-boundary failure")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
