#!/usr/bin/env python3
"""Seed and remove the exact encrypted iOS notification relay fixture.

Ciphertext and Redis credentials never enter a process argument. The encrypted
envelope and a dependency-free helper are sent to the attested relay only over
SSH stdin; the helper itself reads ``/etc/mknoon/relay-server.env``.
"""

from __future__ import annotations

import argparse
import base64
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
from typing import Any, Mapping, NoReturn


SCENARIO = "payload_fast_path_ios_receiver"
STAGING_SCHEMA = "mknoon.sims.ios-payload-fast-path-staging.v1"
REQUEST_SCHEMA = "mknoon.sims.ios-payload-fast-path-provider-request.v1"
PROVIDER_RECEIPT_SCHEMA = "mknoon.sims.ios-payload-fast-path-provider-receipt.v2"
FIXTURE_RECEIPT_SCHEMA = "mknoon.sims.ios-payload-relay-fixture-receipt.v1"
PRIVATE_PAYLOAD_SCHEMA = "mknoon.sims.ios-payload-private-fixture.v1"
LIFECYCLE_SCHEMA = "mknoon.sims.ios-provider-lifecycle.v1"
REMOTE_REQUEST_SCHEMA = "mknoon.sims.ios-payload-relay-remote-request.v1"
REMOTE_RESULT_SCHEMA = "mknoon.sims.ios-payload-relay-remote-result.v1"
_SHA256 = re.compile(r"^[0-9a-f]{64}$")
_GCM_MESSAGE_ID = re.compile(r"^ios-sims-bg-[0-9a-f]{32}$")
_SAFE_TOKEN = re.compile(r"^[A-Za-z0-9._:@+-]{4,256}$")
_RECEIVER = re.compile(r"^[A-Za-z0-9._:-]{4,160}$")
_UTC_MILLISECONDS = re.compile(
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$"
)
_BASE58 = r"[1-9A-HJ-NP-Za-km-z]"
_PEER_ID = re.compile(rf"^(?:12D3KooW{_BASE58}{{44}}|Qm{_BASE58}{{44}})$")
_RELAY_TARGET = re.compile(r"^[A-Za-z0-9._@:-]{3,256}$")
_PENDING_STATE_BY_ACTION = {
    "setup": "fixture_spawn_pending",
    "cleanup": "cleanup_spawn_pending",
    "rollback": "rollback_spawn_pending",
}


class FixtureBlocked(Exception):
    pass


class FixtureFailure(Exception):
    pass


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _sha256_text(value: str) -> str:
    return _sha256_bytes(value.encode("utf-8"))


def _sha256_file(path: Path) -> str:
    return _sha256_bytes(path.read_bytes())


def _canonical(value: object) -> str:
    return json.dumps(value, separators=(",", ":"), sort_keys=True)


def _stable_entry_id(run_id: str, nonce: str, peer_id: str) -> str:
    digest = _sha256_text("\x00".join((run_id, nonce, peer_id)))
    return f"sims-ios-relay-{digest[:32]}"


def _regular_file(raw_path: str, label: str, *, private: bool) -> Path:
    if not raw_path or "\n" in raw_path or "\r" in raw_path:
        raise FixtureBlocked(f"{label} is unavailable")
    path = Path(raw_path).expanduser().absolute()
    try:
        metadata = path.lstat()
    except OSError as error:
        raise FixtureBlocked(f"{label} is unavailable") from error
    if not stat.S_ISREG(metadata.st_mode) or path.is_symlink() or metadata.st_size <= 0:
        raise FixtureBlocked(f"{label} must be a nonempty non-symlink regular file")
    if hasattr(os, "getuid") and metadata.st_uid != os.getuid():
        raise FixtureBlocked(f"{label} is not operator-owned")
    if private and metadata.st_mode & 0o077:
        raise FixtureBlocked(f"{label} permissions are not owner-only")
    return path


def _json_object(path: Path, label: str) -> dict[str, Any]:
    def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise FixtureBlocked(f"{label} contains a duplicate JSON key")
            result[key] = value
        return result

    try:
        decoded = json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=reject_duplicate_keys,
        )
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise FixtureBlocked(f"{label} is not valid JSON") from error
    if not isinstance(decoded, dict):
        raise FixtureBlocked(f"{label} must contain a JSON object")
    return decoded


def _bounded(value: object, maximum: int = 512) -> bool:
    return (
        isinstance(value, str)
        and bool(value.strip())
        and len(value) <= maximum
        and "\n" not in value
        and "\r" not in value
    )


def _exact_apns_one(value: object) -> bool:
    return type(value) is int and value == 1


def _bounded_fixture_text(value: object, maximum: int) -> bool:
    return (
        isinstance(value, str)
        and bool(value)
        and value == value.strip()
        and len(value) <= maximum
        and all(0x20 <= ord(character) <= 0x7E for character in value)
    )


def _decode_base64(value: object, expected_length: int | None = None) -> bytes:
    if not isinstance(value, str) or not value:
        raise FixtureBlocked("encrypted APNs route is incomplete")
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, TypeError) as error:
        raise FixtureBlocked("encrypted APNs route contains invalid base64") from error
    if expected_length is not None and len(decoded) != expected_length:
        raise FixtureBlocked("encrypted APNs route has an invalid field length")
    return decoded


def _validate_lifecycle(
    args: argparse.Namespace,
    lifecycle: Mapping[str, Any],
    request_path: Path,
    staging_path: Path,
    payload_path: Path,
    payload: Mapping[str, Any],
) -> None:
    if (
        _SHA256.fullmatch(str(args.apns_payload_sha256)) is None
        or _SHA256.fullmatch(str(args.receiver_handoff_sha256)) is None
    ):
        raise FixtureBlocked("fixture digest binding is invalid")
    exact = {
        "schema": LIFECYCLE_SCHEMA,
        "state": _PENDING_STATE_BY_ACTION[args.action],
        "runId": args.run_id,
        "nonce": args.nonce,
        "receiverDeviceIdSha256": _sha256_text(args.receiver),
        "peerDeviceIdSha256": _sha256_text(args.peer_device),
        "requestSha256": _sha256_file(request_path),
        "stagingManifestSha256": _sha256_file(staging_path),
        "apnsPayloadSha256": args.apns_payload_sha256,
        "receiverHandoffSha256": args.receiver_handoff_sha256,
        "stagedEnvelopeSha256": _staged_digest(payload),
    }
    if (
        set(lifecycle) != set(exact) | {"recordedAt"}
        or any(lifecycle.get(key) != value for key, value in exact.items())
        or _UTC_MILLISECONDS.fullmatch(str(lifecycle.get("recordedAt", ""))) is None
    ):
        raise FixtureBlocked("provider lifecycle is not bound to this pending mutation")
    if _sha256_file(payload_path) != args.apns_payload_sha256:
        raise FixtureBlocked("encrypted APNs payload bytes do not match their supplied digest")


def _validate_inputs(
    args: argparse.Namespace,
) -> tuple[Path, Path, Path, dict[str, Any], dict[str, Any], dict[str, Any]]:
    if args.scenario != SCENARIO:
        raise FixtureBlocked("fixture scenario is unsupported")
    if _RECEIVER.fullmatch(args.receiver) is None or _PEER_ID.fullmatch(args.peer_device) is None:
        raise FixtureBlocked("fixture receiver binding is invalid")
    if args.receiver == args.peer_device:
        raise FixtureBlocked("hardware and transport receiver identities must differ")
    if any(_SAFE_TOKEN.fullmatch(value) is None for value in (args.run_id, args.nonce)):
        raise FixtureBlocked("fixture run binding is invalid")
    if (
        _RELAY_TARGET.fullmatch(args.relay_target) is None
        or args.relay_target.startswith("-")
        or args.relay_target.count("@") > 1
    ):
        raise FixtureBlocked("relay SSH target is invalid")
    if os.environ.get("SIMS_CHILD_BUILDS_FORBIDDEN") != "1" or os.environ.get(
        "SIMS_MANUAL_ACTIONS_FORBIDDEN"
    ) != "1":
        raise FixtureBlocked("fixture requires automated no-child-build execution")

    relay_key = _regular_file(args.relay_key, "relay SSH key", private=True)
    request_path = _regular_file(args.provider_request, "provider request", private=True)
    staging_path = _regular_file(args.staging_manifest, "staging manifest", private=False)
    payload_path = _regular_file(args.apns_payload, "encrypted APNs payload", private=True)
    lifecycle_path = _regular_file(args.lifecycle, "provider lifecycle", private=True)
    request = _json_object(request_path, "provider request")
    staging = _json_object(staging_path, "staging manifest")
    payload = _json_object(payload_path, "encrypted APNs payload")
    lifecycle = _json_object(lifecycle_path, "provider lifecycle")

    if request.get("schema") != REQUEST_SCHEMA:
        raise FixtureBlocked("provider request schema is unsupported")
    if set(request) != {
        "schema",
        "expectedTitle",
        "expectedBody",
        "expectedMessageText",
        "receiverDeviceId",
        "peerDeviceId",
    }:
        raise FixtureBlocked("provider request fields are not exact")
    for key, maximum in (
        ("expectedTitle", 30),
        ("expectedBody", 512),
        ("expectedMessageText", 140),
    ):
        if not _bounded_fixture_text(request.get(key), maximum):
            raise FixtureBlocked("provider request contains an invalid bounded field")
    for key in ("receiverDeviceId", "peerDeviceId"):
        if not _bounded(request.get(key), 512):
            raise FixtureBlocked("provider request contains an invalid bounded field")
    message_text = str(request["expectedMessageText"])
    if message_text in str(request["expectedTitle"]) or message_text in str(
        request["expectedBody"]
    ):
        raise FixtureBlocked("provider request alert exposes expectedMessageText")
    if request.get("receiverDeviceId") != args.receiver or request.get("peerDeviceId") != args.peer_device:
        raise FixtureBlocked("provider request is not bound to this receiver")

    exact_staging = {
        "schema": STAGING_SCHEMA,
        "environment": "staging",
        "provider": "apns",
        "apnsEnvironment": "development",
        "signingEntitlementEnvironment": "development",
        "relayActive": True,
        "relayInboxSeedDriverAvailable": True,
        "providerCleanupAvailable": True,
        "productionDeploymentPerformed": False,
        "receiverDeviceId": args.receiver,
        "peerDeviceId": args.peer_device,
    }
    if any(staging.get(key) != value for key, value in exact_staging.items()):
        raise FixtureBlocked("staging manifest is not bound to the sandbox relay fixture")
    if not _bounded(staging.get("candidateRelayRevision"), 256) or _SHA256.fullmatch(
        str(staging.get("candidateRelaySha256", ""))
    ) is None:
        raise FixtureBlocked("staging relay attestation is invalid")

    aps = payload.get("aps")
    alert = aps.get("alert") if isinstance(aps, dict) else None
    if (
        set(payload)
        != {
            "fixture_schema",
            "aps",
            "type",
            "sender_id",
            "message_id",
            "gcm.message_id",
            "kem",
            "ciphertext",
            "nonce",
        }
        or not isinstance(alert, dict)
        or set(aps) != {"alert", "mutable-content", "content-available"}
        or set(alert) != {"title", "body"}
        or alert.get("title") != request.get("expectedTitle")
        or alert.get("body") != request.get("expectedBody")
        or not _exact_apns_one(aps.get("mutable-content"))
        or not _exact_apns_one(aps.get("content-available"))
        or _GCM_MESSAGE_ID.fullmatch(str(payload.get("gcm.message_id", "")))
        is None
        or payload.get("fixture_schema") != PRIVATE_PAYLOAD_SCHEMA
        or payload.get("type") != "new_message"
        or _PEER_ID.fullmatch(str(payload.get("sender_id", ""))) is None
        or not _bounded(payload.get("message_id"), 256)
    ):
        raise FixtureBlocked("encrypted APNs payload is not bound to the provider request")
    _decode_base64(payload.get("kem"), 1088)
    ciphertext = _decode_base64(payload.get("ciphertext"))
    _decode_base64(payload.get("nonce"), 12)
    if len(ciphertext) <= 16:
        raise FixtureBlocked("encrypted APNs route ciphertext is invalid")
    if request["expectedMessageText"] in _canonical(payload):
        raise FixtureBlocked("encrypted APNs payload exposes fixture plaintext")
    _validate_lifecycle(
        args,
        lifecycle,
        request_path,
        staging_path,
        payload_path,
        payload,
    )
    return relay_key, request_path, payload_path, request, staging, payload


def _envelope(payload: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "type": "chat_message",
        "version": "2",
        "id": payload["message_id"],
        "senderPeerId": payload["sender_id"],
        "encrypted": {
            "kem": payload["kem"],
            "ciphertext": payload["ciphertext"],
            "nonce": payload["nonce"],
        },
    }


def _staged_digest(payload: Mapping[str, Any]) -> str:
    staged = {
        "kind": "chat",
        "messageId": payload["message_id"],
        "kem": payload["kem"],
        "ciphertext": payload["ciphertext"],
        "nonce": payload["nonce"],
        "senderPeerId": payload["sender_id"],
    }
    return _sha256_text(_canonical(staged))


def _remote_request(
    args: argparse.Namespace,
    staging: Mapping[str, Any],
    payload_path: Path,
    payload: Mapping[str, Any],
) -> dict[str, Any]:
    envelope_text = _canonical(_envelope(payload))
    return {
        "schema": REMOTE_REQUEST_SCHEMA,
        "action": args.action,
        "runId": args.run_id,
        "nonce": args.nonce,
        "peerDeviceId": args.peer_device,
        "senderPeerId": payload["sender_id"],
        "entryId": _stable_entry_id(args.run_id, args.nonce, args.peer_device),
        "encryptedEnvelope": envelope_text,
        "apnsPayloadSha256": _sha256_file(payload_path),
        "encryptedEnvelopeSha256": _sha256_text(envelope_text),
        "stagedEnvelopeSha256": _staged_digest(payload),
        "expectedRelayRevision": staging["candidateRelayRevision"],
        "expectedRelaySha256": staging["candidateRelaySha256"],
    }


def _minimal_environment() -> dict[str, str]:
    result: dict[str, str] = {}
    for key in ("PATH", "HOME", "TMPDIR", "LANG", "LC_ALL", "SSH_AUTH_SOCK"):
        value = os.environ.get(key)
        if value:
            result[key] = value
    return result


def _ssh_executable() -> str:
    resolved = shutil.which("ssh")
    if resolved is None:
        raise FixtureBlocked("OpenSSH client is unavailable")
    return resolved


def _remote_source(request: Mapping[str, Any]) -> bytes:
    helper = Path(__file__).with_name("ios_notification_relay_remote_helper.py")
    try:
        source = helper.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise FixtureBlocked("relay remote helper source is unavailable") from error
    encoded_request = base64.b64encode(_canonical(request).encode("utf-8")).decode("ascii")
    invocation = (
        "\n\n# Request bytes are carried only in SSH stdin.\n"
        f"REQUEST_BYTES = base64.b64decode({json.dumps(encoded_request)})\n"
        "remote_cli(REQUEST_BYTES)\n"
    )
    return (source + invocation).encode("utf-8")


def _run_remote(
    args: argparse.Namespace,
    relay_key: Path,
    request: Mapping[str, Any],
) -> dict[str, Any]:
    command = [
        _ssh_executable(),
        "-T",
        "-i",
        str(relay_key),
        "-o",
        "BatchMode=yes",
        "-o",
        "IdentitiesOnly=yes",
        "-o",
        "StrictHostKeyChecking=yes",
        "-o",
        "LogLevel=ERROR",
        "-o",
        "ConnectTimeout=10",
        "--",
        args.relay_target,
        "sudo",
        "-n",
        "python3",
        "-",
    ]
    try:
        result = subprocess.run(
            command,
            input=_remote_source(request),
            capture_output=True,
            env=_minimal_environment(),
            timeout=45,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise FixtureBlocked("relay SSH helper is unavailable") from error
    if result.returncode == 78:
        raise FixtureBlocked("live relay configuration does not match staging")
    if result.returncode != 0:
        raise FixtureFailure("relay fixture mutation failed closed")
    try:
        decoded = json.loads(result.stdout.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError) as error:
        raise FixtureFailure("relay fixture helper returned an invalid result") from error
    if not isinstance(decoded, dict):
        raise FixtureFailure("relay fixture helper returned an invalid result")
    return decoded


def _validate_remote_result(
    result: Mapping[str, Any],
    request: Mapping[str, Any],
) -> None:
    expected_status = "seeded" if request["action"] == "setup" else "cleared"
    exact = {
        "schema": REMOTE_RESULT_SCHEMA,
        "action": request["action"],
        "status": expected_status,
        "apnsPayloadSha256": request["apnsPayloadSha256"],
        "encryptedEnvelopeSha256": request["encryptedEnvelopeSha256"],
        "stagedEnvelopeSha256": request["stagedEnvelopeSha256"],
        "liveRelaySha256": request["expectedRelaySha256"],
    }
    if any(result.get(key) != value for key, value in exact.items()):
        raise FixtureFailure("relay fixture result is not bound to the exact payload")
    if _SHA256.fullmatch(str(result.get("liveRelayRevisionSha256", ""))) is None:
        raise FixtureFailure("relay fixture result omitted revision attestation")
    if not isinstance(result.get("mutated"), bool):
        raise FixtureFailure("relay fixture result omitted mutation status")
    removed = result.get("removedCount")
    if request["action"] == "setup":
        if removed != 0 or _SHA256.fullmatch(str(result.get("relayEntrySha256", ""))) is None:
            raise FixtureFailure("relay fixture setup omitted exact entry custody")
    elif removed not in (0, 1) or (removed == 1 and _SHA256.fullmatch(str(result.get("relayEntrySha256", ""))) is None):
        raise FixtureFailure("relay fixture cleanup did not remove at most one exact entry")


def _provider_receipt_sha(args: argparse.Namespace, request: Mapping[str, Any]) -> str:
    if not args.provider_receipt:
        raise FixtureBlocked("cleanup requires the exact provider receipt")
    path = _regular_file(args.provider_receipt, "provider receipt", private=True)
    receipt = _json_object(path, "provider receipt")
    expected = {
        "schema": PROVIDER_RECEIPT_SCHEMA,
        "status": "accepted",
        "runId": args.run_id,
        "nonce": args.nonce,
        "receiverDeviceIdSha256": _sha256_text(args.receiver),
        "requestSha256": _sha256_file(Path(args.provider_request).absolute()),
        "apnsPayloadSha256": request["apnsPayloadSha256"],
        "receiverHandoffSha256": args.receiver_handoff_sha256,
        "stagedEnvelopeSha256": request["stagedEnvelopeSha256"],
    }
    if any(receipt.get(key) != value for key, value in expected.items()):
        raise FixtureBlocked("provider receipt is not bound to this exact cleanup")
    return _sha256_file(path)


def _write_private_json(path: Path, value: Mapping[str, Any]) -> None:
    path = path.expanduser().absolute()
    if "\n" in str(path) or "\r" in str(path):
        raise FixtureFailure("fixture receipt path is invalid")
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.is_symlink():
        raise FixtureFailure("fixture receipt path is a symlink")
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write((_canonical(value) + "\n").encode("utf-8"))
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        path.chmod(0o600)
    finally:
        if temporary.exists():
            temporary.unlink()


def _receipt(
    args: argparse.Namespace,
    request_path: Path,
    remote_request: Mapping[str, Any],
    remote_result: Mapping[str, Any],
    provider_receipt_sha: str | None,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "schema": FIXTURE_RECEIPT_SCHEMA,
        "action": args.action,
        "status": "seeded" if args.action == "setup" else "cleared",
        "runId": args.run_id,
        "nonce": args.nonce,
        "receiverDeviceIdSha256": _sha256_text(args.receiver),
        "peerDeviceIdSha256": _sha256_text(args.peer_device),
        "requestSha256": _sha256_file(request_path),
        "childBuildCount": 0,
        "manualActionCount": 0,
        "apnsPayloadSha256": remote_request["apnsPayloadSha256"],
        "receiverHandoffSha256": args.receiver_handoff_sha256,
        "encryptedEnvelopeSha256": remote_request["encryptedEnvelopeSha256"],
        "stagedEnvelopeSha256": remote_request["stagedEnvelopeSha256"],
        "relayBinarySha256": remote_result["liveRelaySha256"],
        "relayRevisionAttestationSha256": remote_result["liveRelayRevisionSha256"],
        "idempotentReplay": not remote_result["mutated"],
    }
    relay_entry_sha = remote_result.get("relayEntrySha256")
    if relay_entry_sha is not None:
        result["relayEntrySha256"] = relay_entry_sha
    if args.action == "setup":
        result["relayInboxSeeded"] = True
    else:
        result["relayFixtureCleared"] = True
    if args.action == "cleanup":
        result["providerReceiptSha256"] = provider_receipt_sha
    return result


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Manage an exact encrypted iOS relay fixture")
    parser.add_argument("--action", required=True, choices=("setup", "cleanup", "rollback"))
    parser.add_argument("--scenario", required=True)
    parser.add_argument("--receiver", required=True)
    parser.add_argument("--peer-device", required=True)
    parser.add_argument("--provider-request", required=True)
    parser.add_argument("--staging-manifest", required=True)
    parser.add_argument("--relay-target", required=True)
    parser.add_argument("--relay-key", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--nonce", required=True)
    parser.add_argument("--apns-payload", required=True)
    parser.add_argument("--apns-payload-sha256", required=True)
    parser.add_argument("--receiver-handoff-sha256", required=True)
    parser.add_argument("--lifecycle", required=True)
    parser.add_argument("--provider-receipt")
    parser.add_argument("--output", required=True)
    return parser


def _blocked(detail: str) -> NoReturn:
    print(f"iOS relay fixture blocked: {detail}", file=sys.stderr)
    raise SystemExit(78)


def _failed(detail: str) -> NoReturn:
    print(f"iOS relay fixture failed: {detail}", file=sys.stderr)
    raise SystemExit(1)


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        relay_key, request_path, payload_path, _, staging, payload = _validate_inputs(args)
        remote_request = _remote_request(args, staging, payload_path, payload)
        if remote_request["apnsPayloadSha256"] != args.apns_payload_sha256:
            raise FixtureBlocked("encrypted APNs payload changed after lifecycle validation")
        provider_sha = (
            _provider_receipt_sha(args, remote_request) if args.action == "cleanup" else None
        )
        remote_result = _run_remote(args, relay_key, remote_request)
        _validate_remote_result(remote_result, remote_request)
        receipt = _receipt(
            args,
            request_path,
            remote_request,
            remote_result,
            provider_sha,
        )
        _write_private_json(Path(args.output), receipt)
    except FixtureBlocked as error:
        _blocked(str(error))
    except FixtureFailure as error:
        _failed(str(error))
    except Exception:
        _failed("unexpected typed-boundary failure")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
