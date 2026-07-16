#!/usr/bin/env python3
"""Capture a private APNs/provider handoff from an existing iPhone app.

The helper never installs or uninstalls the app, never resets its data, and
never prints the APNs device token. All devicectl transfer files live in an
owner-only temporary directory and are removed in ``finally``. The designated
handoff output is a 0600 input for the provider adapter and must be removed by
that caller after the bounded campaign.
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
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from typing import Any, NoReturn


BUNDLE_ID = "com.mknoon.app"
REQUEST_SCHEMA = "mknoon.sims.ios-receiver-bootstrap-request.v1"
HANDOFF_SCHEMA = "mknoon.sims.ios-provider-receiver-handoff.v1"
DEVICE_DIRECTORY = "Library/Application Support/mknoon.sims.ios-receiver-bootstrap"
DEVICE_REQUEST = f"{DEVICE_DIRECTORY}/request.json"
DEVICE_RESPONSE = f"{DEVICE_DIRECTORY}/response.json"
DEVICE_SENDER_REQUEST = f"{DEVICE_DIRECTORY}/sender-request.json"
DEVICE_SENDER_RESULT = f"{DEVICE_DIRECTORY}/sender-result.json"
SENDER_REQUEST_SCHEMA = "mknoon.sims.ios-sender-projection-request.v1"
SENDER_RESULT_SCHEMA = "mknoon.sims.ios-sender-projection-result.v1"
SENDER_HOST_RECEIPT_SCHEMA = "mknoon.sims.ios-sender-projection-host-receipt.v1"
PRIVATE_PAYLOAD_SCHEMA = "mknoon.sims.ios-payload-private-fixture.v1"
RESULT_PREFIX = "IOS_RECEIVER_BOOTSTRAP_RESULT_JSON="
SENDER_RESULT_PREFIX = "IOS_SENDER_PROJECTION_RESULT_JSON="

_SAFE_ID = re.compile(r"^[A-Za-z0-9._:-]{4,160}$")
_SAFE_NONCE = re.compile(r"^[A-Za-z0-9._:-]{12,160}$")
_BASE58 = r"[1-9A-HJ-NP-Za-km-z]"
_PEER_ID = re.compile(rf"^(?:12D3KooW{_BASE58}{{44}}|Qm{_BASE58}{{44}})$")
_APNS_TOKEN = re.compile(r"^[0-9a-f]{64}$")
_ML_KEM_PUBLIC = re.compile(r"^[A-Za-z0-9_+/=-]{100,4096}$")
_SHA256 = re.compile(r"^[0-9a-f]{64}$")
_RESULT_CODE = re.compile(r"^[a-z_]{2,64}$")


def _is_exact_ml_kem_public(value: object) -> bool:
    if not isinstance(value, str) or _ML_KEM_PUBLIC.fullmatch(value) is None:
        return False
    normalized = value.replace("-", "+").replace("_", "/")
    normalized += "=" * ((-len(normalized)) % 4)
    try:
        return len(base64.b64decode(normalized, validate=True)) == 1184
    except (ValueError, binascii.Error):
        return False


class BootstrapBlocked(Exception):
    """The installed app/device/private-output prerequisite is unavailable."""


class BootstrapFailure(Exception):
    """The configured bootstrap ran but did not produce a valid handoff."""


def _utc(value: datetime.datetime) -> str:
    return value.astimezone(datetime.timezone.utc).isoformat(
        timespec="milliseconds"
    ).replace("+00:00", "Z")


def _parse_utc(value: object) -> datetime.datetime | None:
    if not isinstance(value, str) or not value.endswith("Z"):
        return None
    try:
        parsed = datetime.datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError:
        return None
    return parsed.astimezone(datetime.timezone.utc)


def _private_atomic_write(path: Path, data: bytes) -> None:
    path = path.expanduser().absolute()
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        metadata = None
    if metadata is not None:
        if not stat.S_ISREG(metadata.st_mode) or path.is_symlink():
            raise BootstrapBlocked("private handoff output must be a regular file")
        if hasattr(os, "getuid") and metadata.st_uid != os.getuid():
            raise BootstrapBlocked("private handoff output has the wrong owner")
    temporary = path.parent / f".{path.name}.{os.getpid()}.tmp"
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "wb", closefd=True) as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        os.chmod(path, 0o600)
    except BaseException:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
        raise


def _write_json_private(path: Path, value: dict[str, Any]) -> None:
    _private_atomic_write(
        path,
        (json.dumps(value, separators=(",", ":"), sort_keys=True) + "\n").encode(
            "utf-8"
        ),
    )


def _read_handoff(path: Path, *, nonce: str, receiver: str) -> dict[str, Any]:
    try:
        metadata = path.lstat()
        raw = path.read_bytes()
        decoded = json.loads(raw)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise BootstrapFailure("the private receiver handoff is unreadable") from error
    if (
        not stat.S_ISREG(metadata.st_mode)
        or path.is_symlink()
        or metadata.st_mode & 0o077
        or not isinstance(decoded, dict)
        or len(raw) > 8192
    ):
        raise BootstrapFailure("the private receiver handoff is not protected JSON")
    exact_keys = {
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
        "capturedAt",
    }
    captured_at = _parse_utc(decoded.get("capturedAt"))
    now = datetime.datetime.now(datetime.timezone.utc)
    if (
        set(decoded) != exact_keys
        or decoded.get("schema") != HANDOFF_SCHEMA
        or decoded.get("captureNonce") != nonce
        or decoded.get("receiverDeviceId") != receiver
        or decoded.get("bundleId") != BUNDLE_ID
        or decoded.get("apnsEnvironment") != "development"
        or _PEER_ID.fullmatch(str(decoded.get("peerDeviceId", ""))) is None
        or _APNS_TOKEN.fullmatch(str(decoded.get("apnsDeviceToken", ""))) is None
        or not _is_exact_ml_kem_public(decoded.get("mlKemPublicKey"))
        or decoded.get("notificationAuthorization")
        not in {"authorized", "provisional", "ephemeral"}
        or decoded.get("notificationAlertSetting") != "enabled"
        or captured_at is None
        or captured_at > now + datetime.timedelta(seconds=15)
        or now - captured_at > datetime.timedelta(minutes=5)
    ):
        raise BootstrapFailure("the private receiver handoff failed nonce/schema validation")
    return decoded


class _DeviceControl:
    def __init__(self, *, receiver: str, temporary: Path) -> None:
        configured = os.environ.get(
            "SIMS_IOS_RECEIVER_BOOTSTRAP_XCRUN", ""
        ).strip()
        executable = Path(configured).expanduser().absolute() if configured else None
        if executable is None:
            resolved = shutil.which("xcrun")
            if resolved is None:
                raise BootstrapBlocked("xcrun is unavailable")
            executable = Path(resolved)
        if not executable.is_file() or not os.access(executable, os.X_OK):
            raise BootstrapBlocked("the configured xcrun executable is unavailable")
        self.executable = executable
        self.receiver = receiver
        self.temporary = temporary
        self.command_index = 0

    def run(
        self,
        arguments: list[str],
        label: str,
        timeout: int = 30,
        trailing: list[str] | None = None,
    ) -> bool:
        self.command_index += 1
        json_output = self.temporary / f"{self.command_index}-{label}.json"
        log_output = self.temporary / f"{self.command_index}-{label}.log"
        command = [
            str(self.executable),
            "devicectl",
            *arguments,
            "--json-output",
            str(json_output),
            "--log-output",
            str(log_output),
            "--quiet",
            *(trailing or []),
        ]
        try:
            result = subprocess.run(
                command,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=timeout,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            return False
        return result.returncode == 0

    def launch(self, label: str) -> bool:
        return self.run(
            [
                "device",
                "process",
                "launch",
                "--device",
                self.receiver,
                "--terminate-existing",
            ],
            label,
            trailing=[BUNDLE_ID],
        )

    def copy_to(
        self,
        source: Path,
        label: str,
        destination: str = DEVICE_REQUEST,
    ) -> bool:
        return self.run(
            [
                "device",
                "copy",
                "to",
                "--device",
                self.receiver,
                "--source",
                str(source),
                "--destination",
                destination,
                "--domain-type",
                "appDataContainer",
                "--domain-identifier",
                BUNDLE_ID,
            ],
            label,
        )

    def copy_from(
        self,
        destination: Path,
        label: str,
        source: str = DEVICE_RESPONSE,
    ) -> bool:
        return self.run(
            [
                "device",
                "copy",
                "from",
                "--device",
                self.receiver,
                "--source",
                source,
                "--destination",
                str(destination),
                "--domain-type",
                "appDataContainer",
                "--domain-identifier",
                BUNDLE_ID,
            ],
            label,
        )


def _request(
    *, action: str, nonce: str, receiver: str, now: datetime.datetime
) -> dict[str, Any]:
    return {
        "schema": REQUEST_SCHEMA,
        "action": action,
        "captureNonce": nonce,
        "receiverDeviceId": receiver,
        "bundleId": BUNDLE_ID,
        "expiresAt": _utc(now + datetime.timedelta(minutes=3)),
    }


def _read_private_sender_payload(path: Path) -> tuple[dict[str, Any], bytes]:
    try:
        metadata = path.lstat()
        raw = path.read_bytes()
        payload = json.loads(raw)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise BootstrapBlocked("the private encrypted APNs payload is unreadable") from error
    if (
        not stat.S_ISREG(metadata.st_mode)
        or path.is_symlink()
        or metadata.st_mode & 0o077
        or (hasattr(os, "getuid") and metadata.st_uid != os.getuid())
        or not isinstance(payload, dict)
        or not raw
        or len(raw) > 4096
    ):
        raise BootstrapBlocked("the encrypted APNs payload is not protected JSON")
    aps = payload.get("aps")
    alert = aps.get("alert") if isinstance(aps, dict) else None
    exact_keys = {
        "fixture_schema",
        "aps",
        "type",
        "sender_id",
        "message_id",
        "kem",
        "ciphertext",
        "nonce",
    }
    sender = payload.get("sender_id")
    username = alert.get("title") if isinstance(alert, dict) else None
    if (
        set(payload) != exact_keys
        or payload.get("fixture_schema") != PRIVATE_PAYLOAD_SCHEMA
        or payload.get("type") != "new_message"
        or not isinstance(aps, dict)
        or set(aps) != {"alert", "mutable-content"}
        or aps.get("mutable-content") != 1
        or isinstance(aps.get("mutable-content"), bool)
        or not isinstance(alert, dict)
        or set(alert) != {"title", "body"}
        or not isinstance(username, str)
        or username != username.strip()
        or not username
        or len(username) > 30
        or any(ord(character) < 32 or ord(character) == 127 for character in username)
        or not isinstance(sender, str)
        or _PEER_ID.fullmatch(sender) is None
        or any(
            not isinstance(payload.get(key), str) or not payload[key]
            for key in ("message_id", "kem", "ciphertext", "nonce")
        )
    ):
        raise BootstrapBlocked("the encrypted APNs payload has no exact sender route")
    return payload, raw


def _sender_fixture_digest(
    *, nonce: str, receiver: str, sender: str, username: str, payload_sha: str
) -> str:
    value = {
        "schema": SENDER_REQUEST_SCHEMA,
        "captureNonce": nonce,
        "receiverDeviceId": receiver,
        "bundleId": BUNDLE_ID,
        "senderPeerId": sender,
        "senderUsername": username,
        "apnsPayloadSha256": payload_sha,
    }
    canonical = json.dumps(
        value,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def _sender_request(
    *,
    action: str,
    nonce: str,
    receiver: str,
    sender: str,
    username: str,
    payload_sha: str,
    now: datetime.datetime,
) -> dict[str, Any]:
    return {
        "schema": SENDER_REQUEST_SCHEMA,
        "action": action,
        "captureNonce": nonce,
        "receiverDeviceId": receiver,
        "bundleId": BUNDLE_ID,
        "senderPeerId": sender,
        "senderUsername": username,
        "apnsPayloadSha256": payload_sha,
        "createdAt": _utc(now),
        "expiresAt": _utc(now + datetime.timedelta(minutes=3)),
    }


def _read_sender_result(
    path: Path,
    *,
    action: str,
    nonce: str,
    receiver: str,
    payload_sha: str,
    fixture_digest: str,
) -> dict[str, Any]:
    try:
        metadata = path.lstat()
        raw = path.read_bytes()
        result = json.loads(raw)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise BootstrapFailure("the private sender projection result is unreadable") from error
    expected_status = "seeded" if action == "seed_sender" else "cleaned"
    completed_at = _parse_utc(result.get("completedAt") if isinstance(result, dict) else None)
    now = datetime.datetime.now(datetime.timezone.utc)
    exact_keys = {
        "schema",
        "action",
        "captureNonce",
        "receiverDeviceId",
        "bundleId",
        "apnsPayloadSha256",
        "fixtureDigest",
        "status",
        "resultCode",
        "completedAt",
    }
    if (
        not stat.S_ISREG(metadata.st_mode)
        or path.is_symlink()
        or metadata.st_mode & 0o077
        or not isinstance(result, dict)
        or len(raw) > 4096
        or set(result) != exact_keys
        or result.get("schema") != SENDER_RESULT_SCHEMA
        or result.get("action") != action
        or result.get("captureNonce") != nonce
        or result.get("receiverDeviceId") != receiver
        or result.get("bundleId") != BUNDLE_ID
        or result.get("apnsPayloadSha256") != payload_sha
        or result.get("fixtureDigest") != fixture_digest
        or result.get("status") != expected_status
        or _RESULT_CODE.fullmatch(str(result.get("resultCode", ""))) is None
        or completed_at is None
        or completed_at > now + datetime.timedelta(seconds=15)
        or now - completed_at > datetime.timedelta(minutes=5)
    ):
        raise BootstrapFailure("the sender projection result failed exact binding validation")
    return result


def _sender_projection_action(args: argparse.Namespace) -> dict[str, Any]:
    receiver = args.receiver.strip()
    nonce = args.nonce.strip()
    if _SAFE_ID.fullmatch(receiver) is None or _SAFE_NONCE.fullmatch(nonce) is None:
        raise BootstrapBlocked("receiver or capture nonce is invalid")
    payload_path = Path(args.payload).expanduser().absolute()
    receipt_path = Path(args.sender_receipt).expanduser().absolute()
    try:
        receipt_path.unlink()
    except FileNotFoundError:
        pass
    except OSError as error:
        raise BootstrapBlocked("the sender projection receipt cannot be replaced") from error
    payload, payload_raw = _read_private_sender_payload(payload_path)
    sender = str(payload["sender_id"])
    username = str(payload["aps"]["alert"]["title"])
    payload_sha = hashlib.sha256(payload_raw).hexdigest()
    fixture_digest = _sender_fixture_digest(
        nonce=nonce,
        receiver=receiver,
        sender=sender,
        username=username,
        payload_sha=payload_sha,
    )
    native_action = (
        "seed_sender" if args.action == "seed-sender" else "cleanup_sender"
    )
    timeout = max(5, min(args.timeout_seconds, 180))
    native_result: dict[str, Any] | None = None
    with tempfile.TemporaryDirectory(prefix="mknoon-ios-sender-projection-") as raw:
        temporary = Path(raw)
        os.chmod(temporary, 0o700)
        control = _DeviceControl(receiver=receiver, temporary=temporary)
        request_path = temporary / "sender-request.json"
        pulled_result = temporary / "sender-result.json"
        final_cleanup_request = temporary / "final-cleanup-request.json"
        final_cleanup_probe = temporary / "final-cleanup-probe.json"
        _write_json_private(
            request_path,
            _sender_request(
                action=native_action,
                nonce=nonce,
                receiver=receiver,
                sender=sender,
                username=username,
                payload_sha=payload_sha,
                now=datetime.datetime.now(datetime.timezone.utc),
            ),
        )
        if not control.launch("sender-prepare-container"):
            raise BootstrapBlocked(
                "the bootstrap-enabled app is not launchable on the selected iPhone"
            )
        time.sleep(0.25)
        if not control.copy_to(
            request_path,
            "stage-sender-command",
            DEVICE_SENDER_REQUEST,
        ):
            raise BootstrapFailure("the protected sender command could not be staged")
        if not control.launch("process-sender-command"):
            raise BootstrapFailure("the app could not process the sender command")
        deadline = time.monotonic() + timeout
        attempt = 0
        while time.monotonic() < deadline:
            attempt += 1
            try:
                pulled_result.unlink()
            except FileNotFoundError:
                pass
            if control.copy_from(
                pulled_result,
                f"pull-sender-result-{attempt}",
                DEVICE_SENDER_RESULT,
            ):
                try:
                    os.chmod(pulled_result, 0o600)
                except OSError:
                    pass
                native_result = _read_sender_result(
                    pulled_result,
                    action=native_action,
                    nonce=nonce,
                    receiver=receiver,
                    payload_sha=payload_sha,
                    fixture_digest=fixture_digest,
                )
                break
            time.sleep(0.5)
        if native_result is None:
            raise BootstrapFailure("the app did not finish the sender command in time")

        if args.action == "cleanup-sender":
            _write_json_private(
                final_cleanup_request,
                _request(
                    action="cleanup",
                    nonce=nonce,
                    receiver=receiver,
                    now=datetime.datetime.now(datetime.timezone.utc),
                ),
            )
            if not (
                control.copy_to(final_cleanup_request, "stage-final-cleanup")
                and control.launch("final-cleanup")
            ):
                raise BootstrapFailure("sender result cleanup could not be staged")
            time.sleep(0.25)
            if control.copy_from(
                final_cleanup_probe,
                "verify-sender-result-cleanup",
                DEVICE_SENDER_RESULT,
            ):
                raise BootstrapFailure("sender result cleanup did not complete")

    assert native_result is not None
    host_receipt = {
        "schema": SENDER_HOST_RECEIPT_SCHEMA,
        "action": args.action,
        "status": "PASS",
        "containsSecrets": False,
        "bundleId": BUNDLE_ID,
        "captureNonceSha256": hashlib.sha256(nonce.encode()).hexdigest(),
        "receiverDeviceIdSha256": hashlib.sha256(receiver.encode()).hexdigest(),
        "senderPeerIdSha256": hashlib.sha256(sender.encode()).hexdigest(),
        "apnsPayloadSha256": payload_sha,
        "fixtureDigest": fixture_digest,
        "nativeStatus": native_result["status"],
        "resultCode": native_result["resultCode"],
        "completedAt": native_result["completedAt"],
    }
    _write_json_private(receipt_path, host_receipt)
    return host_receipt


def _capture(args: argparse.Namespace) -> dict[str, Any]:
    receiver = args.receiver.strip()
    nonce = args.nonce.strip()
    if _SAFE_ID.fullmatch(receiver) is None or _SAFE_NONCE.fullmatch(nonce) is None:
        raise BootstrapBlocked("receiver or capture nonce is invalid")
    output = Path(args.output).expanduser().absolute()
    timeout = max(5, min(args.timeout_seconds, 180))

    primary: BaseException | None = None
    cleanup_failed = False
    handoff: dict[str, Any] | None = None
    with tempfile.TemporaryDirectory(prefix="mknoon-ios-receiver-bootstrap-") as raw:
        temporary = Path(raw)
        os.chmod(temporary, 0o700)
        control = _DeviceControl(receiver=receiver, temporary=temporary)
        capture_request = temporary / "capture-request.json"
        cleanup_request = temporary / "cleanup-request.json"
        pulled_response = temporary / "receiver-handoff.json"
        cleanup_probe = temporary / "cleanup-response-probe.json"
        _write_json_private(
            capture_request,
            _request(
                action="capture",
                nonce=nonce,
                receiver=receiver,
                now=datetime.datetime.now(datetime.timezone.utc),
            ),
        )
        try:
            if not control.copy_to(capture_request, "stage-capture"):
                if not control.launch("prepare-container"):
                    raise BootstrapBlocked(
                        "the bootstrap-enabled app is not launchable on the selected iPhone"
                    )
                time.sleep(0.25)
                if not control.copy_to(capture_request, "stage-capture-after-prepare"):
                    raise BootstrapFailure(
                        "the protected capture request could not be staged"
                    )
            if not control.launch("capture"):
                raise BootstrapFailure("the installed app could not process the capture request")

            deadline = time.monotonic() + timeout
            attempt = 0
            while time.monotonic() < deadline:
                attempt += 1
                try:
                    pulled_response.unlink()
                except FileNotFoundError:
                    pass
                if control.copy_from(pulled_response, f"pull-{attempt}"):
                    try:
                        os.chmod(pulled_response, 0o600)
                    except OSError:
                        pass
                    handoff = _read_handoff(
                        pulled_response,
                        nonce=nonce,
                        receiver=receiver,
                    )
                    break
                time.sleep(0.5)
            if handoff is None:
                raise BootstrapFailure(
                    "the app did not publish a nonce-bound receiver handoff in time"
                )
            _write_json_private(output, handoff)
        except BaseException as error:
            primary = error
        finally:
            try:
                _write_json_private(
                    cleanup_request,
                    _request(
                        action="cleanup",
                        nonce=nonce,
                        receiver=receiver,
                        now=datetime.datetime.now(datetime.timezone.utc),
                    ),
                )
                cleanup_failed = not (
                    control.copy_to(cleanup_request, "stage-cleanup")
                    and control.launch("cleanup")
                )
                if not cleanup_failed:
                    time.sleep(0.25)
                    cleanup_failed = control.copy_from(
                        cleanup_probe, "verify-cleanup"
                    )
            except BaseException:
                cleanup_failed = True

    if primary is not None:
        try:
            output.unlink()
        except FileNotFoundError:
            pass
        raise primary
    if cleanup_failed:
        try:
            output.unlink()
        except FileNotFoundError:
            pass
        raise BootstrapFailure("the app-container receiver handoff cleanup failed")
    assert handoff is not None
    return handoff


def _required(value: str | None, environment_name: str) -> str:
    resolved = (value or os.environ.get(environment_name, "")).strip()
    if not resolved:
        raise BootstrapBlocked(f"{environment_name} is required")
    return resolved


def _die(status: str, detail: str, code: int) -> NoReturn:
    print(
        RESULT_PREFIX
        + json.dumps(
            {
                "schema": "mknoon.sims.ios-receiver-bootstrap-result.v1",
                "status": status,
                "containsSecrets": False,
                "detail": detail,
            },
            separators=(",", ":"),
            sort_keys=True,
        )
    )
    raise SystemExit(code)


def _sender_die(status: str, detail: str, code: int) -> NoReturn:
    print(
        SENDER_RESULT_PREFIX
        + json.dumps(
            {
                "schema": SENDER_HOST_RECEIPT_SCHEMA,
                "status": status,
                "containsSecrets": False,
                "detail": detail,
            },
            separators=(",", ":"),
            sort_keys=True,
        )
    )
    raise SystemExit(code)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Capture a protected iOS APNs/provider receiver handoff"
    )
    parser.add_argument(
        "--action",
        choices=("capture-receiver", "seed-sender", "cleanup-sender"),
        default="capture-receiver",
    )
    parser.add_argument("--receiver")
    parser.add_argument("--nonce")
    parser.add_argument("--output")
    parser.add_argument("--payload")
    parser.add_argument("--sender-receipt")
    parser.add_argument("--timeout-seconds", type=int, default=120)
    options = parser.parse_args()
    sender_action = options.action in {"seed-sender", "cleanup-sender"}
    try:
        options.receiver = _required(options.receiver, "SIMS_IOS_PHYSICAL_DEVICE_ID")
        options.nonce = _required(
            options.nonce, "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE"
        )
        if sender_action:
            options.payload = _required(
                options.payload, "SIMS_IOS_NOTIFICATION_APNS_PAYLOAD_PATH"
            )
            options.sender_receipt = _required(
                options.sender_receipt,
                "SIMS_IOS_NOTIFICATION_SENDER_PROJECTION_RECEIPT_PATH",
            )
            receipt = _sender_projection_action(options)
        else:
            options.output = _required(
                options.output, "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_PATH"
            )
            handoff = _capture(options)
    except BootstrapBlocked as error:
        if sender_action:
            _sender_die("BLOCKED", str(error), 78)
        _die("BLOCKED", str(error), 78)
    except BootstrapFailure as error:
        if sender_action:
            _sender_die("FAIL", str(error), 1)
        _die("FAIL", str(error), 1)
    except BaseException as error:
        if sender_action:
            _sender_die(
                "FAIL",
                f"sender projection stopped: {error.__class__.__name__}",
                1,
            )
        _die("FAIL", f"receiver bootstrap stopped: {error.__class__.__name__}", 1)

    if sender_action:
        print(
            SENDER_RESULT_PREFIX
            + json.dumps(receipt, separators=(",", ":"), sort_keys=True)
        )
        return

    print(
        RESULT_PREFIX
        + json.dumps(
            {
                "schema": "mknoon.sims.ios-receiver-bootstrap-result.v1",
                "status": "PASS",
                "containsSecrets": False,
                "receiverDeviceId": handoff["receiverDeviceId"],
                "peerDeviceId": handoff["peerDeviceId"],
                "bundleId": handoff["bundleId"],
                "apnsEnvironment": handoff["apnsEnvironment"],
                "handoffPath": str(Path(options.output).expanduser().absolute()),
            },
            separators=(",", ":"),
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
