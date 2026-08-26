#!/usr/bin/env python3
"""Plan-398-only staging transaction for the iOS group-message diagnostic.

This file deliberately coordinates the existing Sims builder, device runner,
and Plan-257 staging relay.  It is not a second notification harness.  The
outer ``run`` process owns a non-reentrant lock through verified restoration;
the capture child calls ``claim-send`` at the one network-send boundary using
the inherited, private active-transaction lease.  ``manual-trace`` reuses the
same lock and retained relay binaries but performs no mobile preparation or
staging-manifest replacement.
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import fcntl
import hashlib
import json
import os
import plistlib
import re
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Mapping, Sequence


SCENARIO = "ios_chat_group_message_and_reaction_recipient"
CAMPAIGN_OWNER = "diagnostic"
RECEIPT_SCHEMA = "mknoon.plan398.staging-deployment-receipt.v1"
SNAPSHOT_SCHEMA = "mknoon.plan398.prepared-snapshot.v1"
LEASE_SCHEMA = "mknoon.plan398.active-transaction-lease.v1"
CLAIM_SCHEMA = "mknoon.plan398.diagnostic-attempt-claim.v1"
RESTORATION_SCHEMA = "mknoon.plan398.restoration-state.v1"
SETUP_PREPARATION_SCHEMA = "mknoon.plan398.ios-setup-preparation.v1"
PRECLAIM_ARCHIVE_SCHEMA = "mknoon.plan398.preclaim-attempt-archive.v1"
MANUAL_PRECLAIM_ARCHIVE_SCHEMA = (
    "mknoon.plan398.manual-preclaim-attempt-archive.v1"
)
FINAL_MANUAL_PRECLAIM_ARCHIVE_SCHEMA = (
    "mknoon.plan398.final-manual-preclaim-attempt-archive.v2"
)
FINAL_ATTEMPT_AUTHORIZATION = (
    "plan398-reviewed-final-same-container-manual-trace-v1"
)
FINAL_ATTEMPT_PIXEL_ID = "21071FDF600CSC"
FINAL_ATTEMPT_01_RECEIPT_SHA256 = (
    "760ac4280f93415845b31c30b7cfbd1e4d0e10efccb4d626ebcd376605295060"
)
FINAL_ATTEMPT_01_HASHES = {
    "journalSha256": (
        "f62874be7b49f3593d5d5d72b5aa95ea0b646ebf0426f3dc45011c3bde0b023d"
    ),
    "deviceLogSha256": (
        "553071a186a7d4a69b1c8c54814c1aaddc68d9145b7dcf8f9d8615f39ff5e615"
    ),
    "traceManifestSha256": (
        "65e23da2bffb949f0491fb00ac3de875d56063ef4307fc6f5f78d121ecf7f729"
    ),
    "traceRelayStateSha256": (
        "b0e1d7d2ac2ebf40c827224b7ac124340f11ef4cad0f6f0d00484e2b9bd32d69"
    ),
}
FINAL_ATTEMPT_02_HASHES = {
    "journalSha256": (
        "8b0da6ebd454a5696b4971507485b7f2e3f319eef0cb60fc0e25676c60acf2c3"
    ),
    "deviceLogSha256": (
        "3c6432e0726599d4143ee4858afccc57c452a47058c95f1564ab59fb3074f0b2"
    ),
    "traceManifestSha256": (
        "65e23da2bffb949f0491fb00ac3de875d56063ef4307fc6f5f78d121ecf7f729"
    ),
    "traceRelayStateSha256": (
        "b0e1d7d2ac2ebf40c827224b7ac124340f11ef4cad0f6f0d00484e2b9bd32d69"
    ),
}
FINAL_ATTEMPT_FAILURE_SHA256 = (
    "d160e1e70f53b0651c91dfd45401daf26b0a0c7f001b659ca1c9eb3a3070900a"
)
FINAL_RUNNER_RECIPIENT = "00008030-001A6D2801BB802E"
FINAL_RUNNER_BUNDLE_ID = "com.mknoon.app"
FINAL_RUNNER_ARTIFACT_RELATIVE = Path(
    "build/plan398/tc398-10-existing-state"
)
FINAL_RUNNER_NAMESPACE_NAME = "final-runner-update"
FINAL_RUNNER_AUTHORIZED_RETRY_ATTEMPT = "authorized-retry-01"
FINAL_RUNNER_AUTHORIZED_RETRY_AUTHORIZATION = (
    "plan398-reviewed-authorized-retry-01-v1"
)
FINAL_RUNNER_AUTHORIZED_RETRY_NAMESPACE_NAME = (
    "final-runner-update-authorized-retry-01"
)
FINAL_RUNNER_AUTHORIZED_RETRY_PRODUCT_NAME = "Runner.app"
FINAL_RUNNER_ORIGINAL_FAILED_BUILD_CLAIM_SHA256 = (
    "b2b3f0aa09d46801fa1c27b00e7a53f23b45b5de5d9f4f9fd14c08130b1e82bb"
)
FINAL_RUNNER_ORIGINAL_FAILED_BUILD_RECEIPT_SHA256 = (
    "16a9cddbce4a4d1abc36c15ab29814caa314e1cd0d2e929350ea7ec7834dc5b5"
)
FINAL_RUNNER_AUTHORIZED_RETRY_LIVE_ARTIFACT_RELATIVE = Path(
    "build/plan398/direct-live-diagnostic-authorized-retry-01"
)
FINAL_RUNNER_FIRST_LIVE_TRACE_RELATIVE = Path(
    "build/plan398/direct-live-diagnostic"
)
FINAL_RUNNER_FIRST_LIVE_TRACE_HASHES = {
    "device_logcat_21071FDF600CSC.log": (
        "0fbe7bda02513ce1a7ad961deca7af925f54e19b2d2581c82af82876288abd48"
    ),
    "plan398_existing_state_trace_claim.json": (
        "61864d4bd82bf6c9b402c5c02aec06cc806a7ffd18cb1620f593def2c55ec28a"
    ),
    "plan398_existing_state_trace_command_journal.json": (
        "4c54050ba116bd6293caf90c83c8f78eeb598d63de191c07bebe1e2aaadb2e94"
    ),
    "plan398_existing_state_trace_failure.json": (
        "0db67704bbe9524ea5cfa50568e11c8ea7a3e86f229b1ba0b72f279dadd65fbf"
    ),
    "plan398_existing_state_trace_ios_stderr.bin": (
        "359e8f7fdd3ccfcfb1e6cbd8673371df921d6e11d4438ef2e0c9179f48198bdb"
    ),
    "plan398_existing_state_trace_ios_stdout.bin": (
        "300add8c08636ce75a71c4d0ab29b11d79197918c3585d635b8acd75ce368f31"
    ),
    "plan398_existing_state_trace_manifest.json": (
        "65e23da2bffb949f0491fb00ac3de875d56063ef4307fc6f5f78d121ecf7f729"
    ),
    "plan398_existing_state_trace_relay_state.json": (
        "2552ac8d08f24015753fde92f32f9037c4ebaa93bace864074c92decfebd4f49"
    ),
    "plan398_existing_state_trace_terminal_receipt.json": (
        "c7f2069be321d1615899d50e96789fb3758b2213b78eb8b7e0dd2dd9e069375f"
    ),
}
FINAL_RUNNER_BUILD_CLAIM_SCHEMA = (
    "mknoon.plan398.final-runner-build-claim.v1"
)
FINAL_RUNNER_BUILD_RECEIPT_SCHEMA = (
    "mknoon.plan398.final-runner-build-terminal-receipt.v1"
)
FINAL_RUNNER_INSTALL_CLAIM_SCHEMA = (
    "mknoon.plan398.final-runner-install-claim.v1"
)
FINAL_RUNNER_INSTALL_RECEIPT_SCHEMA = (
    "mknoon.plan398.final-runner-install-terminal-receipt.v1"
)
FINAL_RUNNER_XCODE_BUILD_SETTINGS = {
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": (
        "$(inherited) MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP"
    ),
}
FINAL_RUNNER_FLUTTER_BUILD_ENVIRONMENT = {
    f"FLUTTER_XCODE_{key}": value
    for key, value in FINAL_RUNNER_XCODE_BUILD_SETTINGS.items()
}
FINAL_RUNNER_BUILD_ENVIRONMENT_REMOVALS = (
    "DART_DEFINES",
    "E2E_TEST_MODE",
    "FLUTTER_TARGET",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS",
)
FINAL_RUNNER_BUILD_ENVIRONMENT_PREFIX_REMOVALS = (
    "FLUTTER_XCODE_",
    "SIMS_BUILD_",
)
FINAL_RUNNER_BUILD_CLAIM_NAME = "build-claim.json"
FINAL_RUNNER_BUILD_RECEIPT_NAME = "build-terminal-receipt.json"
FINAL_RUNNER_INSTALL_CLAIM_NAME = "install-claim.json"
FINAL_RUNNER_INSTALL_RECEIPT_NAME = "install-terminal-receipt.json"
CURRENT_SOURCE_RESTART_SCHEMA = (
    "mknoon.plan398.preclaim-current-source-restart.v1"
)
CURRENT_SOURCE_RESTART_AUTHORIZATION = (
    "plan398-reviewed-current-source-restart-v1"
)
DIAGNOSTIC_ARTIFACT_SCHEMA = "mknoon.plan398.ios-group-message-diagnostic.v1"
PRIOR_AUTHORITY_SCHEMA = "mknoon.plan397.deployment-state.v1"
IOS_SETUP_PROFILE = "ios.device.group_reaction_notification_397"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SAFE_ID_RE = re.compile(r"^[A-Za-z0-9._:-]{1,160}$")
SAFE_TARGET_RE = re.compile(r"^[A-Za-z0-9._@:-]{3,255}$")
TRACE_MANIFEST_SCHEMA = "mknoon.plan398.existing-state-trace-manifest.v1"
TRACE_RELAY_STATE_SCHEMA = "mknoon.plan398.manual-trace-relay-state.v1"
TRACE_ARTIFACT_NAME = "plan398_existing_state_trace.json"
TRACE_CLAIM_NAME = "plan398_existing_state_trace_claim.json"
TRACE_FAILURE_NAME = "plan398_existing_state_trace_failure.json"
TRACE_MANIFEST_NAME = "plan398_existing_state_trace_manifest.json"
TRACE_RELAY_STATE_NAME = "plan398_existing_state_trace_relay_state.json"
TRACE_TERMINAL_RECEIPT_NAME = (
    "plan398_existing_state_trace_terminal_receipt.json"
)
TRACE_AUTHORIZED_RETRY_RECEIPT_NAME = (
    "plan398_authorized_retry_01_live_terminal_receipt.json"
)
TRACE_AUTHORIZED_RETRY_RECEIPT_SCHEMA = (
    "mknoon.plan398.authorized-retry-01-live-terminal-receipt.v1"
)
TRACE_CLAIM_SCHEMA = "mknoon.plan398.existing-state-trace-claim.v1"
TRACE_LIVE_ARTIFACT_SCHEMA = (
    "mknoon.plan398.ios-group-message-existing-state-live-diagnostic.v1"
)
TRACE_LIVE_TERMINAL_RECEIPT_SCHEMA = (
    "mknoon.plan398.existing-state-live-diagnostic-terminal-receipt.v1"
)
TRACE_LIVE_AUTHORITY_MODE = "live_diagnostic"
TRACE_LIVE_DISPOSITIONS = {
    "repo_owned_duplicate_dispatch",
    "candidate_single_unattributed_duplicate",
    "claim_absent_or_noncandidate",
    "local_contender",
    "clean_nonreproduction",
}


class IncompleteEvidence(RuntimeError):
    """A typed fail-closed diagnostic blocker."""


class InterruptedTransaction(RuntimeError):
    def __init__(self, signum: int) -> None:
        super().__init__(f"interrupted_by_signal_{signum}")
        self.signum = signum


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _sha256_text(value: str) -> str:
    return _sha256_bytes(value.encode("utf-8"))


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _entity_digest(path: Path) -> str:
    """Hash a file or a directory without following symlinks."""

    if path.is_symlink() or not path.exists():
        raise IncompleteEvidence("prepared_artifact_missing_or_symlinked")
    if path.is_file():
        return _sha256_file(path)
    if not path.is_dir():
        raise IncompleteEvidence("prepared_artifact_has_unsupported_type")
    digest = hashlib.sha256()
    for entry in sorted(path.rglob("*"), key=lambda item: item.relative_to(path).as_posix()):
        if entry.is_symlink():
            raise IncompleteEvidence("prepared_artifact_contains_symlink")
        relative = entry.relative_to(path).as_posix().encode("utf-8")
        mode = stat.S_IMODE(entry.stat().st_mode)
        digest.update(b"D\0" if entry.is_dir() else b"F\0")
        digest.update(relative)
        digest.update(b"\0")
        digest.update(f"{mode:o}".encode("ascii"))
        digest.update(b"\0")
        if entry.is_file():
            with entry.open("rb") as source:
                while chunk := source.read(1024 * 1024):
                    digest.update(chunk)
    return digest.hexdigest()


def _application_digest(path: Path) -> str:
    """Match the capture driver's signed-app directory digest exactly."""

    if path.is_symlink() or not path.is_dir():
        raise IncompleteEvidence("ios_setup_application_missing_or_symlinked")
    digest = hashlib.sha256()
    files: list[Path] = []
    for entry in path.rglob("*"):
        if entry.is_symlink():
            raise IncompleteEvidence("ios_setup_application_contains_symlink")
        if entry.is_file():
            files.append(entry)
    for entry in sorted(files, key=lambda item: item.relative_to(path).as_posix()):
        relative = entry.relative_to(path).as_posix()
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        with entry.open("rb") as source:
            while chunk := source.read(1024 * 1024):
                digest.update(chunk)
        digest.update(b"\0")
    return digest.hexdigest()


def _canonical_json(value: Mapping[str, Any]) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode(
        "utf-8"
    )


def _fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _write_atomic(path: Path, payload: bytes, *, private: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent
    )
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600 if private else 0o644)
        with os.fdopen(descriptor, "wb", closefd=True) as destination:
            destination.write(payload)
            destination.flush()
            os.fsync(destination.fileno())
        os.replace(temporary, path)
        os.chmod(path, 0o600 if private else 0o644)
        _fsync_directory(path.parent)
    finally:
        if temporary.exists():
            temporary.unlink()


def _write_json_atomic(path: Path, value: Mapping[str, Any], *, private: bool) -> None:
    _write_atomic(path, _canonical_json(value), private=private)


def _write_no_replace(
    path: Path,
    payload: bytes,
    *,
    private: bool,
    code: str,
) -> None:
    """Durably publish one file without replacing any existing path."""

    if _path_present(path) or not path.parent.is_dir():
        raise IncompleteEvidence(code)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent
    )
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600 if private else 0o644)
        with os.fdopen(descriptor, "wb", closefd=True) as destination:
            destination.write(payload)
            destination.flush()
            os.fsync(destination.fileno())
        try:
            os.link(temporary, path, follow_symlinks=False)
        except OSError as error:
            raise IncompleteEvidence(code) from error
        os.chmod(path, 0o600 if private else 0o644)
        _fsync_directory(path.parent)
    finally:
        if temporary.exists():
            temporary.unlink()


def _retain_equal(path: Path, payload: bytes, *, private: bool = False) -> None:
    if path.exists():
        if not path.is_file() or path.read_bytes() != payload:
            raise IncompleteEvidence(f"retained_product_mismatch_{path.name}")
        return
    _write_atomic(path, payload, private=private)


def _read_json(path: Path, code: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise IncompleteEvidence(code) from error
    if not isinstance(value, dict):
        raise IncompleteEvidence(code)
    return value


def _require_sha(value: Any, code: str) -> str:
    if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
        raise IncompleteEvidence(code)
    return value


def _continuity_stable_fields(
    sample: Any,
    code: str,
) -> dict[str, Any]:
    """Validate one filesystem-continuity sample and discard diagnostics."""

    if not isinstance(sample, dict) or set(sample) != {
        "recipient",
        "bundleIdentifier",
        "inventory",
        "afcRoot",
        "identityDatabase",
    }:
        raise IncompleteEvidence(code)
    inventory = sample.get("inventory")
    root = sample.get("afcRoot")
    database = sample.get("identityDatabase")
    if (
        sample.get("recipient") != FINAL_RUNNER_RECIPIENT
        or sample.get("bundleIdentifier") != FINAL_RUNNER_BUNDLE_ID
        or not isinstance(inventory, dict)
        or set(inventory)
        != {
            "bundleIdentifier",
            "bundleShortVersion",
            "bundleVersion",
            "executableName",
            "appDataContainer",
            "url",
        }
        or inventory.get("bundleIdentifier") != FINAL_RUNNER_BUNDLE_ID
        or inventory.get("executableName") != "Runner"
    ):
        raise IncompleteEvidence(code)
    for key in ("bundleShortVersion", "bundleVersion"):
        value = inventory.get(key)
        if not isinstance(value, str) or not value or "\n" in value:
            raise IncompleteEvidence(code)
    app_url = inventory.get("url")
    if not isinstance(app_url, str) or not app_url or "\n" in app_url:
        raise IncompleteEvidence(code)
    literal_app_path = (
        app_url[7:] if app_url.startswith("file://") else app_url
    ).rstrip("/")
    if (
        not literal_app_path.startswith("/")
        or "<" in app_url
        or ">" in app_url
        or Path(literal_app_path).name != "Runner.app"
    ):
        raise IncompleteEvidence(code)
    container = inventory.get("appDataContainer")
    if container is not None:
        if (
            not isinstance(container, str)
            or not container
            or "\n" in container
            or "<" in container
            or ">" in container
        ):
            raise IncompleteEvidence(code)
        literal_container = (
            container[7:] if container.startswith("file://") else container
        )
        if not literal_container.startswith("/"):
            raise IncompleteEvidence(code)
    if (
        not isinstance(root, dict)
        or set(root) != {"path", "st_ifmt", "st_birthtime"}
        or root.get("path") != "/"
        or root.get("st_ifmt") != "S_IFDIR"
        or isinstance(root.get("st_birthtime"), bool)
        or not isinstance(root.get("st_birthtime"), int)
        or root["st_birthtime"] <= 0
    ):
        raise IncompleteEvidence(code)
    if (
        not isinstance(database, dict)
        or set(database)
        != {"path", "st_ifmt", "st_birthtime", "diagnostics"}
        or database.get("path") != "Documents/identity.db"
        or database.get("st_ifmt") != "S_IFREG"
        or isinstance(database.get("st_birthtime"), bool)
        or not isinstance(database.get("st_birthtime"), int)
        or database["st_birthtime"] <= 0
    ):
        raise IncompleteEvidence(code)
    diagnostics = database.get("diagnostics")
    if (
        not isinstance(diagnostics, dict)
        or set(diagnostics) != {"st_nlink", "st_size", "st_mtime", "sha256"}
        or diagnostics.get("st_nlink") != 1
        or isinstance(diagnostics.get("st_size"), bool)
        or not isinstance(diagnostics.get("st_size"), int)
        or diagnostics["st_size"] <= 0
        or isinstance(diagnostics.get("st_mtime"), bool)
        or not isinstance(diagnostics.get("st_mtime"), int)
        or diagnostics["st_mtime"] < 0
    ):
        raise IncompleteEvidence(code)
    _require_sha(diagnostics.get("sha256"), code)
    return {
        "recipient": sample["recipient"],
        "bundleIdentifier": sample["bundleIdentifier"],
        "appDataContainer": container,
        "afcRoot": dict(root),
        "identityDatabase": {
            "path": database["path"],
            "st_ifmt": database["st_ifmt"],
            "st_birthtime": database["st_birthtime"],
        },
    }


def _require_private(path: Path, code: str) -> None:
    try:
        mode = stat.S_IMODE(path.stat().st_mode)
    except OSError as error:
        raise IncompleteEvidence(code) from error
    if mode & 0o077:
        raise IncompleteEvidence(code)


def _require_private_regular(path: Path, code: str) -> os.stat_result:
    """Require one distinct, non-symlinked mode-0600 evidence file."""

    try:
        metadata = path.lstat()
    except OSError as error:
        raise IncompleteEvidence(code) from error
    if (
        not stat.S_ISREG(metadata.st_mode)
        or stat.S_IMODE(metadata.st_mode) != 0o600
        or metadata.st_nlink != 1
    ):
        raise IncompleteEvidence(code)
    return metadata


def _final_attempt_member_paths(archive: Path) -> dict[str, Path]:
    return {
        "journalSha256": (
            archive / "plan398_existing_state_trace_command_journal.json"
        ),
        "deviceLogSha256": (
            archive / f"device_logcat_{FINAL_ATTEMPT_PIXEL_ID}.log"
        ),
        "traceManifestSha256": archive / TRACE_MANIFEST_NAME,
        "traceRelayStateSha256": archive / TRACE_RELAY_STATE_NAME,
    }


def _validate_fixed_final_attempt_archive(
    archive: Path,
    *,
    expected_receipt: Mapping[str, Any],
    expected_hashes: Mapping[str, str],
    code: str,
) -> dict[str, str]:
    """Validate an exact receipt-last attempt entity without following links."""

    if (
        archive.is_symlink()
        or not archive.is_dir()
        or stat.S_IMODE(archive.stat().st_mode) != 0o700
    ):
        raise IncompleteEvidence(f"{code}_archive_invalid")
    receipt = archive / "receipt.json"
    members = _final_attempt_member_paths(archive)
    expected_names = {receipt.name, *(path.name for path in members.values())}
    try:
        actual_names = {entry.name for entry in archive.iterdir()}
    except OSError as error:
        raise IncompleteEvidence(f"{code}_archive_unreadable") from error
    if actual_names != expected_names:
        raise IncompleteEvidence(f"{code}_archive_entity_changed")

    identities: set[tuple[int, int]] = set()
    for key, member in members.items():
        metadata = _require_private_regular(member, f"{code}_{key}_invalid")
        identity = (metadata.st_dev, metadata.st_ino)
        if identity in identities:
            raise IncompleteEvidence(f"{code}_members_not_distinct")
        identities.add(identity)
        if _sha256_file(member) != expected_hashes[key]:
            raise IncompleteEvidence(f"{code}_{key}_changed")

    receipt_metadata = _require_private_regular(
        receipt, f"{code}_receipt_invalid"
    )
    if (receipt_metadata.st_dev, receipt_metadata.st_ino) in identities:
        raise IncompleteEvidence(f"{code}_receipt_not_distinct")
    receipt_bytes = receipt.read_bytes()
    if (
        receipt_bytes != _canonical_json(expected_receipt)
        or _read_json(receipt, f"{code}_receipt_invalid") != expected_receipt
    ):
        raise IncompleteEvidence(f"{code}_receipt_changed")
    return {
        "entitySha256": _entity_digest(archive),
        "receiptSha256": _sha256_bytes(receipt_bytes),
    }


def _validate_fixed_final_attempt_01(
    artifact_directory: Path,
) -> dict[str, str]:
    """Bind the already-sealed immutable attempt-01 entity."""

    archive_root = artifact_directory / "preclaim-attempts"
    if (
        archive_root.is_symlink()
        or not archive_root.is_dir()
        or stat.S_IMODE(archive_root.stat().st_mode) != 0o700
    ):
        raise IncompleteEvidence("final_runner_attempt_archive_root_invalid")
    attempt_01_receipt = {
        "schema": MANUAL_PRECLAIM_ARCHIVE_SCHEMA,
        "attempt": "attempt-01",
        **FINAL_ATTEMPT_01_HASHES,
    }
    attempt_01 = _validate_fixed_final_attempt_archive(
        archive_root / "attempt-01",
        expected_receipt=attempt_01_receipt,
        expected_hashes=FINAL_ATTEMPT_01_HASHES,
        code="final_runner_attempt_01",
    )
    if attempt_01["receiptSha256"] != FINAL_ATTEMPT_01_RECEIPT_SHA256:
        raise IncompleteEvidence("final_runner_attempt_01_receipt_hash_changed")
    return attempt_01


def _validate_fixed_final_attempt_evidence(
    artifact_directory: Path,
) -> dict[str, Any]:
    """Bind the two sealed pre-claim attempts and the fixed failure bytes."""

    archive_root = artifact_directory / "preclaim-attempts"
    attempt_01 = _validate_fixed_final_attempt_01(artifact_directory)

    attempt_02_receipt = {
        "schema": FINAL_MANUAL_PRECLAIM_ARCHIVE_SCHEMA,
        "attempt": "attempt-02",
        "authorizationId": FINAL_ATTEMPT_AUTHORIZATION,
        "priorAttempt": "attempt-01",
        "priorAttemptReceiptSha256": FINAL_ATTEMPT_01_RECEIPT_SHA256,
        "priorAttemptEntitySha256": attempt_01["entitySha256"],
        **FINAL_ATTEMPT_02_HASHES,
    }
    attempt_02 = _validate_fixed_final_attempt_archive(
        archive_root / "attempt-02",
        expected_receipt=attempt_02_receipt,
        expected_hashes=FINAL_ATTEMPT_02_HASHES,
        code="final_runner_attempt_02",
    )

    failure = artifact_directory / TRACE_FAILURE_NAME
    _require_private_regular(failure, "final_runner_retained_failure_invalid")
    if _sha256_file(failure) != FINAL_ATTEMPT_FAILURE_SHA256:
        raise IncompleteEvidence("final_runner_retained_failure_changed")
    return {
        "attempt01": attempt_01,
        "attempt02": attempt_02,
        "retainedFailureSha256": FINAL_ATTEMPT_FAILURE_SHA256,
    }


def _validate_original_failed_final_runner_namespace(
    artifact_directory: Path,
) -> dict[str, str]:
    """Bind the consumed original build attempt without permitting replay."""

    namespace = artifact_directory / FINAL_RUNNER_NAMESPACE_NAME
    if (
        namespace.is_symlink()
        or not namespace.is_dir()
        or stat.S_IMODE(namespace.stat().st_mode) != 0o700
    ):
        raise IncompleteEvidence(
            "final_runner_retry_original_namespace_invalid"
        )
    claim = namespace / FINAL_RUNNER_BUILD_CLAIM_NAME
    receipt = namespace / FINAL_RUNNER_BUILD_RECEIPT_NAME
    try:
        names = {entry.name for entry in namespace.iterdir()}
    except OSError as error:
        raise IncompleteEvidence(
            "final_runner_retry_original_namespace_unreadable"
        ) from error
    if names != {claim.name, receipt.name}:
        raise IncompleteEvidence(
            "final_runner_retry_original_namespace_entity_changed"
        )
    claim_stat = _require_private_regular(
        claim, "final_runner_retry_original_build_claim_invalid"
    )
    receipt_stat = _require_private_regular(
        receipt, "final_runner_retry_original_build_receipt_invalid"
    )
    if (claim_stat.st_dev, claim_stat.st_ino) == (
        receipt_stat.st_dev,
        receipt_stat.st_ino,
    ):
        raise IncompleteEvidence(
            "final_runner_retry_original_receipts_not_distinct"
        )
    claim_sha = _sha256_file(claim)
    receipt_sha = _sha256_file(receipt)
    if (
        claim_sha != FINAL_RUNNER_ORIGINAL_FAILED_BUILD_CLAIM_SHA256
        or receipt_sha
        != FINAL_RUNNER_ORIGINAL_FAILED_BUILD_RECEIPT_SHA256
    ):
        raise IncompleteEvidence(
            "final_runner_retry_original_namespace_hash_changed"
        )
    claim_value = _read_json(
        claim, "final_runner_retry_original_build_claim_invalid"
    )
    receipt_value = _read_json(
        receipt, "final_runner_retry_original_build_receipt_invalid"
    )
    if (
        claim_value.get("schema") != FINAL_RUNNER_BUILD_CLAIM_SCHEMA
        or receipt_value.get("schema") != FINAL_RUNNER_BUILD_RECEIPT_SCHEMA
        or receipt_value.get("status") != "failed"
        or claim_value.get("authorizationId") != FINAL_ATTEMPT_AUTHORIZATION
        or receipt_value.get("authorizationId")
        != FINAL_ATTEMPT_AUTHORIZATION
        or claim_value.get("recipient") != FINAL_RUNNER_RECIPIENT
        or receipt_value.get("recipient") != FINAL_RUNNER_RECIPIENT
        or claim_value.get("bundleIdentifier") != FINAL_RUNNER_BUNDLE_ID
        or receipt_value.get("bundleIdentifier") != FINAL_RUNNER_BUNDLE_ID
        or receipt_value.get("claimSha256") != claim_sha
    ):
        raise IncompleteEvidence(
            "final_runner_retry_original_namespace_binding_invalid"
        )
    return {
        "namespaceEntitySha256": _entity_digest(namespace),
        "buildClaimSha256": claim_sha,
        "buildReceiptSha256": receipt_sha,
    }


def _validate_first_live_trace(project_root: Path) -> dict[str, Any]:
    """Bind the sealed first live diagnostic as immutable retry provenance."""

    trace = project_root / FINAL_RUNNER_FIRST_LIVE_TRACE_RELATIVE
    if (
        trace.is_symlink()
        or not trace.is_dir()
        or stat.S_IMODE(trace.stat().st_mode) != 0o755
    ):
        raise IncompleteEvidence("final_runner_retry_first_live_trace_invalid")
    try:
        names = {entry.name for entry in trace.iterdir()}
    except OSError as error:
        raise IncompleteEvidence(
            "final_runner_retry_first_live_trace_unreadable"
        ) from error
    if names != set(FINAL_RUNNER_FIRST_LIVE_TRACE_HASHES):
        raise IncompleteEvidence(
            "final_runner_retry_first_live_trace_entity_changed"
        )
    identities: set[tuple[int, int]] = set()
    for name, expected_sha in FINAL_RUNNER_FIRST_LIVE_TRACE_HASHES.items():
        path = trace / name
        metadata = _require_private_regular(
            path, "final_runner_retry_first_live_trace_member_invalid"
        )
        identity = (metadata.st_dev, metadata.st_ino)
        if identity in identities:
            raise IncompleteEvidence(
                "final_runner_retry_first_live_trace_members_not_distinct"
            )
        identities.add(identity)
        if _sha256_file(path) != expected_sha:
            raise IncompleteEvidence(
                "final_runner_retry_first_live_trace_hash_changed"
            )

    claim = _read_json(
        trace / TRACE_CLAIM_NAME,
        "final_runner_retry_first_live_trace_claim_invalid",
    )
    journal = _read_json(
        trace / "plan398_existing_state_trace_command_journal.json",
        "final_runner_retry_first_live_trace_journal_invalid",
    )
    failure = _read_json(
        trace / TRACE_FAILURE_NAME,
        "final_runner_retry_first_live_trace_failure_invalid",
    )
    manifest = _read_json(
        trace / TRACE_MANIFEST_NAME,
        "final_runner_retry_first_live_trace_manifest_invalid",
    )
    relay = _read_json(
        trace / TRACE_RELAY_STATE_NAME,
        "final_runner_retry_first_live_trace_relay_invalid",
    )
    terminal = _read_json(
        trace / TRACE_TERMINAL_RECEIPT_NAME,
        "final_runner_retry_first_live_trace_terminal_invalid",
    )
    if (
        claim.get("schema") != TRACE_CLAIM_SCHEMA
        or claim.get("ownerRunId") != "existing-state-trace"
        or claim.get("singleOwnerDeclared") is not True
        or journal.get("schema") != "mknoon.plan257.command-journal.v1"
        or journal.get("scenario") != SCENARIO
        or failure.get("schema") != "mknoon.plan257.capture-failure.v1"
        or failure.get("status") != "environment_blocked"
        or failure.get("traceAttemptClaimed") is not True
        or manifest.get("schema") != TRACE_MANIFEST_SCHEMA
        or relay.get("schema") != TRACE_RELAY_STATE_SCHEMA
        or relay.get("status") != "restored"
        or relay.get("authorityMode") != TRACE_LIVE_AUTHORITY_MODE
        or terminal.get("schema") != TRACE_LIVE_TERMINAL_RECEIPT_SCHEMA
        or terminal.get("terminalStatus") != "typed_failure"
        or terminal.get("authorityMode") != TRACE_LIVE_AUTHORITY_MODE
        or terminal.get("traceAttemptClaimed") is not True
    ):
        raise IncompleteEvidence(
            "final_runner_retry_first_live_trace_binding_invalid"
        )
    return {
        "directoryEntitySha256": _entity_digest(trace),
        "fileSha256": dict(FINAL_RUNNER_FIRST_LIVE_TRACE_HASHES),
    }


def _validate_authorized_retry_authority(
    artifact_directory: Path,
) -> dict[str, Any]:
    """Revalidate every immutable authority consumed by authorized-retry-01."""

    try:
        project_root = artifact_directory.parents[2]
    except IndexError as error:
        raise IncompleteEvidence(
            "final_runner_retry_artifact_directory_invalid"
        ) from error
    if artifact_directory != project_root / FINAL_RUNNER_ARTIFACT_RELATIVE:
        raise IncompleteEvidence(
            "final_runner_retry_artifact_directory_invalid"
        )
    return {
        "attemptNamespace": FINAL_RUNNER_AUTHORIZED_RETRY_ATTEMPT,
        "authorizationId": FINAL_RUNNER_AUTHORIZED_RETRY_AUTHORIZATION,
        "originalFailedNamespace": (
            _validate_original_failed_final_runner_namespace(
                artifact_directory
            )
        ),
        "evidence": _validate_fixed_final_attempt_evidence(
            artifact_directory
        ),
        "firstLiveTrace": _validate_first_live_trace(project_root),
    }


def _path_present(path: Path) -> bool:
    """Treat broken symlinks as present for every fail-closed state gate."""

    return os.path.lexists(path)


def _command_from_environment(name: str, fallback: Sequence[str]) -> list[str]:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return list(fallback)
    command = shlex.split(raw)
    if not command:
        raise IncompleteEvidence(f"empty_command_override_{name.lower()}")
    return command


def _setup_redacted_command() -> list[str]:
    return [
        "xcodebuild",
        "build-for-testing",
        "-workspace",
        "ios/Runner.xcworkspace",
        "-scheme",
        "Runner",
        "-configuration",
        "Release",
        "ENABLE_TESTABILITY=YES",
        "-destination",
        "generic/platform=iOS",
        "-derivedDataPath",
        "<campaign-temporary>",
        "FLUTTER_TARGET=lib/main.dart",
        "DART_DEFINES=<redacted>",
    ]


def _event(name: str) -> None:
    """Append test-only ordering evidence; never active in a live campaign."""

    path_value = os.environ.get("PLAN398_TEST_EVENT_LOG", "").strip()
    if not path_value:
        return
    path = Path(path_value)
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(descriptor, f"{name}\n".encode("utf-8"))
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _run_command(
    command: Sequence[str],
    *,
    cwd: Path,
    environment: Mapping[str, str] | None = None,
    remove_environment: Sequence[str] = (),
    remove_environment_prefixes: Sequence[str] = (),
    code: str,
    capture: bool = True,
) -> subprocess.CompletedProcess[str]:
    merged = os.environ.copy()
    for name in remove_environment:
        merged.pop(name, None)
    if remove_environment_prefixes:
        for name in tuple(merged):
            if name.startswith(tuple(remove_environment_prefixes)):
                merged.pop(name)
    if environment:
        merged.update(environment)
    try:
        result = subprocess.run(
            list(command),
            cwd=cwd,
            env=merged,
            text=True,
            stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.PIPE if capture else None,
            check=False,
        )
    except OSError as error:
        raise IncompleteEvidence(f"{code}_launch_failed") from error
    if result.returncode != 0:
        raise IncompleteEvidence(f"{code}_failed")
    return result


def _suite_source_digest(project_root: Path) -> str:
    """Compute the exact source inventory used at preparation and claim time."""

    test_source = os.environ.get("PLAN398_TEST_SOURCE_FILE", "").strip()
    if test_source:
        if os.environ.get("PLAN398_TEST_MODE") != "1":
            raise IncompleteEvidence("test_source_override_forbidden")
        source = Path(test_source)
        if not source.is_file():
            raise IncompleteEvidence("test_source_missing")
        return _sha256_file(source)
    roots = (
        "android",
        "go-relay-server",
        "integration_test",
        "ios",
        "lib",
        "scripts/run_test_gates.sh",
        "tool/sims",
        "pubspec.yaml",
        "pubspec.lock",
    )
    result = _run_command(
        [
            "git",
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "--",
            *roots,
        ],
        cwd=project_root,
        code="suite_source_inventory",
    )
    relative_paths = sorted(line for line in result.stdout.splitlines() if line)
    if not relative_paths:
        raise IncompleteEvidence("suite_source_inventory_empty")
    digest = hashlib.sha256()
    for relative in relative_paths:
        path = project_root / relative
        if not path.is_file() or path.is_symlink():
            raise IncompleteEvidence("suite_source_inventory_changed")
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        with path.open("rb") as source:
            while chunk := source.read(1024 * 1024):
                digest.update(chunk)
        digest.update(b"\0")
    return digest.hexdigest()


class Paths:
    def __init__(self, project_root: Path) -> None:
        override = os.environ.get("PLAN398_CAMPAIGN_ROOT", "").strip()
        self.project_root = project_root
        self.campaign = (
            Path(override).resolve()
            if override
            else project_root / "build" / "plan398" / "diagnostic"
        )
        self.claim = self.campaign.parent / "diagnostic-campaign-claimed.json"
        self.lock = self.campaign.parent / "diagnostic-transaction.lock"
        self.receipt = self.campaign / "deployment-state.json"
        self.snapshot = self.campaign / "prepared-snapshot.json"
        self.lease = self.campaign / "active-transaction-lease.json"
        self.restoration = self.campaign / "restoration-state.json"
        self.prior_relay = self.campaign / "prior-relay-server"
        self.candidate_relay = self.campaign / "relay-server-linux-amd64"
        self.prior_manifest = self.campaign / "prior-staging-manifest.json"
        self.candidate_manifest = self.campaign / "candidate-staging-manifest.json"
        self.android_report = self.campaign / "android-preparation-report.json"
        self.ios_report = self.campaign / "ios-preparation-report.json"
        self.android_attestation = self.campaign / "android-attestation.json"
        self.ios_attestation = self.campaign / "ios-attestation.json"
        self.ios_setup_preparation = self.campaign / "ios-setup-preparation"
        self.ios_setup_application = self.ios_setup_preparation / "Runner.app"
        self.ios_setup_receipt = self.ios_setup_preparation / "receipt.json"
        self.artifact_directory = (
            self.campaign / "physical-proof" / "diagnostic-message-window"
        )
        self.artifact = self.artifact_directory / f"{SCENARIO}.json"
        self.preclaim_attempts = self.campaign / "preclaim-attempts"
        self.preclaim_campaign_archives = (
            self.campaign.parent / "preclaim-campaign-archives"
        )
        self.sims_cache = self.campaign / "sims-cache"


def _acquire_transaction_lock(path: Path) -> Any:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
    os.chmod(path, 0o600)
    lock_file = os.fdopen(descriptor, "a+")
    try:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as error:
        lock_file.close()
        raise IncompleteEvidence("diagnostic_transaction_already_active") from error
    return lock_file


class Transaction:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.project_root = Path(args.project_root).resolve()
        self.paths = Paths(self.project_root)
        self.prior_authority_path = Path(args.prior_authority).resolve()
        self.staging_manifest = Path(args.staging_manifest).resolve()
        self.relay_key = Path(args.relay_key).resolve()
        self.service_account = Path(args.service_account).resolve()
        self.relay_target = args.relay_target
        self.relay_addresses = [
            item.strip() for item in args.relay_addresses.split(",") if item.strip()
        ]
        self.child: subprocess.Popen[str] | None = None
        self.deployed = False
        self.restored = False
        self._signal: int | None = None

    def validate_static_inputs(self) -> None:
        if not self.project_root.is_dir():
            raise IncompleteEvidence("project_root_missing")
        if not SAFE_ID_RE.fullmatch(self.args.run_id):
            raise IncompleteEvidence("unsafe_run_id")
        if not SAFE_ID_RE.fullmatch(self.args.sender) or not SAFE_ID_RE.fullmatch(
            self.args.recipient
        ):
            raise IncompleteEvidence("unsafe_device_id")
        if not SAFE_TARGET_RE.fullmatch(self.relay_target):
            raise IncompleteEvidence("unsafe_relay_target")
        if not self.args.single_owner:
            raise IncompleteEvidence("single_owner_declaration_required")
        if not self.relay_addresses:
            raise IncompleteEvidence("relay_addresses_required")
        for required, code in (
            (self.prior_authority_path, "prior_authority_missing"),
            (self.staging_manifest, "staging_manifest_missing"),
            (self.relay_key, "relay_key_missing"),
            (self.service_account, "service_account_missing"),
        ):
            if not required.is_file():
                raise IncompleteEvidence(code)

    def acquire_lock(self) -> Any:
        return _acquire_transaction_lock(self.paths.lock)

    def _prior_authority(self) -> dict[str, Any]:
        authority = _read_json(
            self.prior_authority_path, "prior_authority_invalid_json"
        )
        exact = {
            "schema",
            "runId",
            "relayTargetSha256",
            "stagingManifestPathSha256",
            "priorRelayVersion",
            "priorRelaySha256",
            "candidateRelaySha256",
            "priorManifestSha256",
            "candidateManifestSha256",
        }
        if set(authority) != exact or authority.get("schema") != PRIOR_AUTHORITY_SCHEMA:
            raise IncompleteEvidence("prior_authority_schema_or_shape_invalid")
        for key in (
            "relayTargetSha256",
            "stagingManifestPathSha256",
            "priorRelaySha256",
            "candidateRelaySha256",
            "priorManifestSha256",
            "candidateManifestSha256",
        ):
            _require_sha(authority.get(key), f"prior_authority_{key}_invalid")
        if authority["relayTargetSha256"] != _sha256_text(self.relay_target):
            raise IncompleteEvidence("prior_authority_relay_target_mismatch")
        if authority["stagingManifestPathSha256"] != _sha256_text(
            str(self.staging_manifest)
        ):
            raise IncompleteEvidence("prior_authority_manifest_path_mismatch")
        if not isinstance(authority.get("priorRelayVersion"), str) or not authority[
            "priorRelayVersion"
        ]:
            raise IncompleteEvidence("prior_authority_relay_version_invalid")
        return authority

    def _source_digest(self) -> str:
        return _suite_source_digest(self.project_root)

    def _prepare_profile(
        self,
        *,
        capability: str,
        profile: str,
        temporary_report: Path,
    ) -> tuple[dict[str, Any], bytes, bytes]:
        _event(f"prepare:{profile}")
        command = _command_from_environment(
            "PLAN398_SIMS_COMMAND", ["./scripts/run_test_gates.sh"]
        )
        environment = {
            "SIMS_REPORT_PATH": str(temporary_report),
            "SIMS_CACHE_DIR": str(self.paths.sims_cache),
            "MKNOON_RELAY_ADDRESSES": ",".join(self.relay_addresses),
        }
        _run_command(
            [
                *command,
                "sims",
                "major",
                "--prepare-builds",
                "--only",
                capability,
                "--list",
                "--format",
                "json",
            ],
            cwd=self.project_root,
            environment=environment,
            code=f"sims_prepare_{profile}",
        )
        report_bytes = temporary_report.read_bytes()
        report = _read_json(temporary_report, f"{profile}_report_invalid")
        builds = report.get("builds")
        if not isinstance(builds, dict):
            raise IncompleteEvidence(f"{profile}_build_report_missing")
        digests = builds.get("artifactDigests")
        failed = builds.get("failedProfileIds", [])
        if (
            not isinstance(digests, dict)
            or set(digests) != {profile}
            or failed != []
        ):
            raise IncompleteEvidence(f"{profile}_build_report_not_exact")
        artifact_digest = _require_sha(
            digests.get(profile), f"{profile}_artifact_digest_invalid"
        )
        report_source_digest = _require_sha(
            report.get("sourceDigest"), f"{profile}_report_source_digest_invalid"
        )
        matches: list[tuple[Path, dict[str, Any]]] = []
        profile_root = self.paths.sims_cache / profile
        if profile_root.is_dir():
            for candidate in profile_root.glob("*/attestation.json"):
                try:
                    attestation = _read_json(candidate, "attestation_invalid")
                except IncompleteEvidence:
                    continue
                if (
                    attestation.get("schemaVersion") == 1
                    and attestation.get("profileId") == profile
                    and attestation.get("artifactDigest") == artifact_digest
                ):
                    matches.append((candidate, attestation))
        if len(matches) != 1:
            raise IncompleteEvidence(f"{profile}_attestation_not_unique")
        attestation_path, attestation = matches[0]
        input_digest = _require_sha(
            attestation.get("inputDigest"), f"{profile}_input_digest_invalid"
        )
        artifact_path_value = attestation.get("artifactPath")
        if not isinstance(artifact_path_value, str) or not artifact_path_value:
            raise IncompleteEvidence(f"{profile}_artifact_path_invalid")
        artifact_path = Path(artifact_path_value).resolve()
        if self.paths.sims_cache.resolve() not in artifact_path.parents:
            raise IncompleteEvidence(f"{profile}_artifact_outside_campaign_cache")
        local_digest = _entity_digest(artifact_path)
        attestation_bytes = attestation_path.read_bytes()
        return (
            {
                "profileId": profile,
                "reportSourceDigest": report_source_digest,
                "inputDigest": input_digest,
                "artifactDigest": artifact_digest,
                "artifactEntitySha256": local_digest,
                "artifactPathSha256": _sha256_text(str(artifact_path)),
                "artifactPath": str(artifact_path),
                "attestationSha256": _sha256_bytes(attestation_bytes),
            },
            report_bytes,
            attestation_bytes,
        )

    def _retained_setup_binding(self, suite_source_digest: str) -> dict[str, Any]:
        receipt = _read_json(
            self.paths.ios_setup_receipt, "retained_ios_setup_receipt_invalid"
        )
        exact = {
            "schema",
            "profileId",
            "suiteSourceDigest",
            "applicationRelativePath",
            "artifactEntitySha256",
            "applicationSha256",
            "centralCompileCommands",
            "logicalBuildCount",
            "childBuildCount",
            "redactedCommand",
        }
        if set(receipt) != exact:
            raise IncompleteEvidence("retained_ios_setup_receipt_shape_invalid")
        if (
            receipt.get("schema") != SETUP_PREPARATION_SCHEMA
            or receipt.get("profileId") != IOS_SETUP_PROFILE
            or receipt.get("suiteSourceDigest") != suite_source_digest
            or receipt.get("applicationRelativePath") != "Runner.app"
            or receipt.get("centralCompileCommands") != 1
            or receipt.get("logicalBuildCount") != 1
            or receipt.get("childBuildCount") != 0
        ):
            raise IncompleteEvidence("retained_ios_setup_binding_invalid")
        entity_sha = _require_sha(
            receipt.get("artifactEntitySha256"),
            "retained_ios_setup_entity_sha_invalid",
        )
        application_sha = _require_sha(
            receipt.get("applicationSha256"),
            "retained_ios_setup_application_sha_invalid",
        )
        if receipt.get("redactedCommand") != _setup_redacted_command():
            raise IncompleteEvidence("retained_ios_setup_command_invalid")
        if (
            _entity_digest(self.paths.ios_setup_application) != entity_sha
            or _application_digest(self.paths.ios_setup_application)
            != application_sha
        ):
            raise IncompleteEvidence("retained_ios_setup_artifact_changed")
        return {
            **receipt,
            "receiptSha256": _sha256_file(self.paths.ios_setup_receipt),
            "artifactPath": str(self.paths.ios_setup_application.resolve()),
        }

    def _prepare_setup_application(self, suite_source_digest: str) -> dict[str, Any]:
        _event(f"prepare:{IOS_SETUP_PROFILE}")
        preparation_exists = self.paths.ios_setup_preparation.exists()
        if preparation_exists:
            if not self.paths.ios_setup_preparation.is_dir():
                raise IncompleteEvidence("retained_ios_setup_preparation_invalid")
            return self._retained_setup_binding(suite_source_digest)

        defines = (
            "E2E_TEST_MODE=true",
            f"SIMS_BUILD_PROFILE_ID={IOS_SETUP_PROFILE}",
            f"MKNOON_RELAY_ADDRESSES={','.join(self.relay_addresses)}",
        )
        encoded_defines = ",".join(
            base64.b64encode(value.encode("utf-8")).decode("ascii")
            for value in defines
        )
        command = _command_from_environment(
            "PLAN398_XCODEBUILD_COMMAND", ["xcodebuild"]
        )
        self.paths.campaign.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(
            prefix="ios-setup-derived-", dir=self.paths.campaign
        ) as derived_name:
            derived_data = Path(derived_name)
            arguments = [
                "build-for-testing",
                "-workspace",
                "ios/Runner.xcworkspace",
                "-scheme",
                "Runner",
                "-configuration",
                "Release",
                "ENABLE_TESTABILITY=YES",
                "-destination",
                "generic/platform=iOS",
                "-derivedDataPath",
                str(derived_data),
                "FLUTTER_TARGET=lib/main.dart",
                f"DART_DEFINES={encoded_defines}",
            ]
            _event("ios_setup_build")
            _run_command(
                [*command, *arguments],
                cwd=self.project_root,
                environment={"SIMS_BUILD_PROFILE": IOS_SETUP_PROFILE},
                code="ios_setup_central_build",
                capture=False,
            )
            source = (
                derived_data
                / "Build/Products/Release-iphoneos/Runner.app"
            ).resolve()
            entity_sha = _entity_digest(source)
            application_sha = _application_digest(source)
            receipt = {
                "schema": SETUP_PREPARATION_SCHEMA,
                "profileId": IOS_SETUP_PROFILE,
                "suiteSourceDigest": suite_source_digest,
                "applicationRelativePath": "Runner.app",
                "artifactEntitySha256": entity_sha,
                "applicationSha256": application_sha,
                "centralCompileCommands": 1,
                "logicalBuildCount": 1,
                "childBuildCount": 0,
                "redactedCommand": _setup_redacted_command(),
            }
            temporary = Path(
                tempfile.mkdtemp(
                    prefix=".ios-setup-preparation.", dir=self.paths.campaign
                )
            )
            try:
                shutil.copytree(source, temporary / "Runner.app")
                _write_json_atomic(
                    temporary / "receipt.json", receipt, private=False
                )
                if (
                    _entity_digest(temporary / "Runner.app") != entity_sha
                    or _application_digest(temporary / "Runner.app")
                    != application_sha
                ):
                    raise IncompleteEvidence("copied_ios_setup_artifact_changed")
                os.replace(temporary, self.paths.ios_setup_preparation)
                _fsync_directory(self.paths.campaign)
            finally:
                if temporary.exists():
                    shutil.rmtree(temporary)
        return self._retained_setup_binding(suite_source_digest)

    def _relay_revision(self) -> str:
        source = (self.project_root / "go-relay-server" / "main.go").read_text(
            encoding="utf-8"
        )
        match = re.search(r'^const version = "([A-Za-z0-9._-]+)"$', source, re.M)
        if match is None:
            raise IncompleteEvidence("relay_revision_not_closed")
        return f"relay-server v{match.group(1)}"

    def _build_relay(self, temporary_candidate: Path) -> dict[str, str]:
        _event("relay_build")
        command = _command_from_environment("PLAN398_GO_COMMAND", ["go"])
        environment = {
            "CGO_ENABLED": "0",
            "GOOS": "linux",
            "GOARCH": "amd64",
            "GOTOOLCHAIN": "go1.25.0",
        }
        _run_command(
            [
                *command,
                "build",
                "-trimpath",
                "-buildvcs=false",
                "-ldflags=-buildid=",
                "-o",
                str(temporary_candidate),
                ".",
            ],
            cwd=self.project_root / "go-relay-server",
            environment=environment,
            code="deterministic_linux_relay_build",
        )
        if not temporary_candidate.is_file():
            raise IncompleteEvidence("relay_candidate_missing")
        return {
            "sha256": _sha256_file(temporary_candidate),
            "revision": self._relay_revision(),
        }

    def _retained_profile_binding(
        self, report_path: Path, attestation_path: Path, profile: str
    ) -> dict[str, Any]:
        report = _read_json(report_path, f"retained_{profile}_report_invalid")
        attestation = _read_json(
            attestation_path, f"retained_{profile}_attestation_invalid"
        )
        builds = report.get("builds")
        digests = builds.get("artifactDigests") if isinstance(builds, dict) else None
        if not isinstance(digests, dict):
            raise IncompleteEvidence(f"retained_{profile}_digests_missing")
        artifact_path = Path(str(attestation.get("artifactPath", ""))).resolve()
        return {
            "profileId": profile,
            "reportSourceDigest": _require_sha(
                report.get("sourceDigest"), "retained_report_source_digest_invalid"
            ),
            "inputDigest": _require_sha(
                attestation.get("inputDigest"), "retained_input_digest_invalid"
            ),
            "artifactDigest": _require_sha(
                digests.get(profile), "retained_artifact_digest_invalid"
            ),
            "artifactEntitySha256": _entity_digest(artifact_path),
            "artifactPathSha256": _sha256_text(str(artifact_path)),
            "artifactPath": str(artifact_path),
            "attestationSha256": _sha256_file(attestation_path),
        }

    def _prepare_and_retain(self) -> dict[str, Any]:
        self.paths.campaign.mkdir(parents=True, exist_ok=True)
        source_digest = self._source_digest()
        with tempfile.TemporaryDirectory(
            prefix="prepare-", dir=self.paths.campaign
        ) as temporary_name:
            temporary = Path(temporary_name)
            android, android_report, android_attestation = self._prepare_profile(
                capability="build.android.production_fcm",
                profile="android.production_fcm",
                temporary_report=temporary / "android.json",
            )
            ios, ios_report, ios_attestation = self._prepare_profile(
                capability="build.ios.device.production",
                profile="ios.device.production",
                temporary_report=temporary / "ios.json",
            )
            ios_setup = self._prepare_setup_application(source_digest)
            relay = self._build_relay(temporary / "relay-server")
            if self.paths.candidate_relay.exists():
                if _sha256_file(self.paths.candidate_relay) != relay["sha256"]:
                    raise IncompleteEvidence("retained_relay_candidate_mismatch")
            else:
                _write_atomic(
                    self.paths.candidate_relay,
                    (temporary / "relay-server").read_bytes(),
                    private=False,
                )
                os.chmod(self.paths.candidate_relay, 0o755)

            retained_pairs = (
                (self.paths.android_report, android_report),
                (self.paths.ios_report, ios_report),
                (self.paths.android_attestation, android_attestation),
                (self.paths.ios_attestation, ios_attestation),
            )
            if not self.paths.android_report.exists():
                for path, payload in retained_pairs:
                    _write_atomic(path, payload, private=False)
            else:
                for path, _ in retained_pairs:
                    if not path.is_file():
                        raise IncompleteEvidence("retained_build_product_missing")
                retained_android = self._retained_profile_binding(
                    self.paths.android_report,
                    self.paths.android_attestation,
                    "android.production_fcm",
                )
                retained_ios = self._retained_profile_binding(
                    self.paths.ios_report,
                    self.paths.ios_attestation,
                    "ios.device.production",
                )
                if retained_android != android or retained_ios != ios:
                    raise IncompleteEvidence("retained_mobile_preparation_mismatch")
                # The capture validator rejects reports older than one hour.
                # A markerless resume regenerates both profiles and proves the
                # retained artifact/attestation bindings are still exact above;
                # retain those fresh report bytes instead of reusing the old
                # timestamps at the child boundary.
                _write_atomic(
                    self.paths.android_report, android_report, private=False
                )
                _write_atomic(self.paths.ios_report, ios_report, private=False)

        if self._source_digest() != source_digest:
            raise IncompleteEvidence("suite_source_changed_during_preparation")
        snapshot = {
            "schema": SNAPSHOT_SCHEMA,
            "ownerRunId": CAMPAIGN_OWNER,
            "suiteSourceDigest": source_digest,
            "android": {key: value for key, value in android.items() if key != "artifactPath"},
            "ios": {key: value for key, value in ios.items() if key != "artifactPath"},
            "iosSetup": {
                key: value for key, value in ios_setup.items() if key != "artifactPath"
            },
            "relayCandidateSha256": relay["sha256"],
            "relayRevision": relay["revision"],
        }
        snapshot_bytes = _canonical_json(snapshot)
        _retain_equal(self.paths.snapshot, snapshot_bytes, private=True)
        snapshot["sha256"] = _sha256_bytes(snapshot_bytes)
        snapshot["androidArtifactPath"] = android["artifactPath"]
        snapshot["iosArtifactPath"] = ios["artifactPath"]
        snapshot["iosSetupArtifactPath"] = ios_setup["artifactPath"]
        return snapshot

    def _ssh(self, remote: Sequence[str], code: str) -> str:
        command = _command_from_environment("PLAN398_SSH_COMMAND", ["ssh"])
        result = _run_command(
            [
                *command,
                "-o",
                "BatchMode=yes",
                "-o",
                "ConnectTimeout=15",
                "-i",
                str(self.relay_key),
                self.relay_target,
                shlex.join(remote),
            ],
            cwd=self.project_root,
            code=code,
        )
        return result.stdout.strip()

    def _scp(self, source: str, destination: str, code: str) -> None:
        command = _command_from_environment("PLAN398_SCP_COMMAND", ["scp"])
        _run_command(
            [
                *command,
                "-q",
                "-o",
                "BatchMode=yes",
                "-o",
                "ConnectTimeout=15",
                "-i",
                str(self.relay_key),
                source,
                destination,
            ],
            cwd=self.project_root,
            code=code,
        )

    def _remote_identity(self) -> dict[str, str]:
        active = self._ssh(
            ["systemctl", "is-active", "relay-server"], "relay_active_probe"
        )
        if active != "active":
            raise IncompleteEvidence("staging_relay_not_active")
        installed = self._ssh(
            ["sha256sum", "/usr/local/bin/relay-server"],
            "relay_installed_sha_probe",
        ).split()
        if not installed:
            raise IncompleteEvidence("relay_installed_sha_missing")
        installed_sha = _require_sha(installed[0], "relay_installed_sha_invalid")
        pid = self._ssh(
            [
                "systemctl",
                "show",
                "relay-server",
                "--property=MainPID",
                "--value",
            ],
            "relay_main_pid_probe",
        )
        if not pid.isdigit() or int(pid) <= 1:
            raise IncompleteEvidence("relay_main_pid_invalid")
        running = self._ssh(
            ["sudo", "-n", "sha256sum", f"/proc/{pid}/exe"],
            "relay_running_sha_probe",
        ).split()
        if not running:
            raise IncompleteEvidence("relay_running_sha_missing")
        running_sha = _require_sha(running[0], "relay_running_sha_invalid")
        version = self._ssh(
            ["/usr/local/bin/relay-server", "version"], "relay_version_probe"
        )
        if not version:
            raise IncompleteEvidence("relay_version_missing")
        return {
            "installedSha256": installed_sha,
            "runningSha256": running_sha,
            "version": version,
        }

    def _capture_prior_relay(self, authority: Mapping[str, Any]) -> None:
        if self.paths.prior_relay.exists():
            if _sha256_file(self.paths.prior_relay) != authority["priorRelaySha256"]:
                raise IncompleteEvidence("retained_prior_relay_mismatch")
            return
        identity = self._remote_identity()
        if (
            identity["installedSha256"] != authority["priorRelaySha256"]
            or identity["runningSha256"] != authority["priorRelaySha256"]
            or identity["version"] != authority["priorRelayVersion"]
        ):
            raise IncompleteEvidence("prior_relay_authority_not_live")
        temporary = self.paths.campaign / ".prior-relay-download"
        self._scp(
            f"{self.relay_target}:/usr/local/bin/relay-server",
            str(temporary),
            "prior_relay_download",
        )
        try:
            if _sha256_file(temporary) != authority["priorRelaySha256"]:
                raise IncompleteEvidence("downloaded_prior_relay_mismatch")
            _write_atomic(self.paths.prior_relay, temporary.read_bytes(), private=False)
            os.chmod(self.paths.prior_relay, 0o755)
        finally:
            if temporary.exists():
                temporary.unlink()

    def _candidate_manifest_bytes(
        self, relay: Mapping[str, str], authority: Mapping[str, Any]
    ) -> bytes:
        expected_sha = authority["candidateManifestSha256"]
        templates = [
            path
            for path in sorted(self.prior_authority_path.parent.iterdir())
            if path.is_file()
            and not path.is_symlink()
            and path.name.startswith("staging-manifest.candidate")
            and path.suffix == ".json"
            and _sha256_file(path) == expected_sha
        ]
        if len(templates) != 1:
            raise IncompleteEvidence("prior_candidate_manifest_not_unique_or_missing")
        manifest = _read_json(
            templates[0], "prior_candidate_manifest_invalid"
        )
        manifest["candidateRelayRevision"] = relay["revision"]
        manifest["candidateRelaySha256"] = relay["sha256"]
        manifest["relayAddresses"] = self.relay_addresses
        return _canonical_json(manifest)

    def _prepare_deployment_receipt(
        self, snapshot: Mapping[str, Any], authority: Mapping[str, Any]
    ) -> dict[str, Any]:
        current_manifest_sha = _sha256_file(self.staging_manifest)
        if self.paths.prior_manifest.exists():
            if _sha256_file(self.paths.prior_manifest) != authority["priorManifestSha256"]:
                raise IncompleteEvidence("retained_prior_manifest_mismatch")
        elif current_manifest_sha == authority["priorManifestSha256"]:
            _write_atomic(
                self.paths.prior_manifest,
                self.staging_manifest.read_bytes(),
                private=False,
            )
        else:
            raise IncompleteEvidence("prior_manifest_authority_not_live")

        relay = {
            "sha256": snapshot["relayCandidateSha256"],
            "revision": snapshot["relayRevision"],
        }
        candidate_manifest_bytes = self._candidate_manifest_bytes(relay, authority)
        _retain_equal(
            self.paths.candidate_manifest, candidate_manifest_bytes, private=False
        )
        candidate_manifest_sha = _sha256_bytes(candidate_manifest_bytes)
        receipt = {
            "schema": RECEIPT_SCHEMA,
            "ownerRunId": CAMPAIGN_OWNER,
            "singleOwnerDeclared": True,
            "priorAuthoritySha256": _sha256_file(self.prior_authority_path),
            "relayTargetSha256": _sha256_text(self.relay_target),
            "stagingManifestPathSha256": _sha256_text(str(self.staging_manifest)),
            "suiteSourceDigest": snapshot["suiteSourceDigest"],
            "preparedSnapshotSha256": snapshot["sha256"],
            "android": snapshot["android"],
            "ios": snapshot["ios"],
            "iosSetup": snapshot["iosSetup"],
            "candidateRelaySha256": snapshot["relayCandidateSha256"],
            "candidateRelayRevision": snapshot["relayRevision"],
            "priorRelaySha256": authority["priorRelaySha256"],
            "priorRelayVersion": authority["priorRelayVersion"],
            "priorManifestSha256": authority["priorManifestSha256"],
            "candidateManifestSha256": candidate_manifest_sha,
        }
        receipt_bytes = _canonical_json(receipt)
        _retain_equal(self.paths.receipt, receipt_bytes, private=True)
        receipt["sha256"] = _sha256_bytes(receipt_bytes)
        return receipt

    def _replace_manifest(self, expected_sha: str, source: Path) -> None:
        if _sha256_file(self.staging_manifest) != expected_sha:
            raise IncompleteEvidence("staging_manifest_sha_cas_failed")
        _write_atomic(self.staging_manifest, source.read_bytes(), private=False)

    def _install_remote_binary(self, source: Path, nonce: str, label: str) -> None:
        remote_temporary = f"/tmp/relay-server.plan398.{nonce}"
        _event(f"remote_mutation:{label}:copy")
        self._scp(
            str(source),
            f"{self.relay_target}:{remote_temporary}",
            f"{label}_relay_upload",
        )
        _event(f"remote_mutation:{label}:install")
        self._ssh(
            [
                "sudo",
                "install",
                "-m",
                "0755",
                remote_temporary,
                "/usr/local/bin/relay-server",
            ],
            f"{label}_relay_install",
        )
        self._ssh(
            ["sudo", "systemctl", "restart", "relay-server"],
            f"{label}_relay_restart",
        )
        self._ssh(["rm", "-f", remote_temporary], f"{label}_relay_cleanup")

    def _deploy(
        self,
        snapshot: Mapping[str, Any],
        receipt: Mapping[str, Any],
        authority: Mapping[str, Any],
        nonce: str,
    ) -> None:
        self._capture_prior_relay(authority)
        current = _sha256_file(self.staging_manifest)
        if current != authority["priorManifestSha256"]:
            raise IncompleteEvidence("fresh_deploy_manifest_not_prior")
        # From this point every exception and catchable signal must take the
        # verified restoration path before the transaction lock is released.
        self.deployed = True
        _event("remote_mutation:manifest_candidate")
        self._replace_manifest(current, self.paths.candidate_manifest)
        self._install_remote_binary(self.paths.candidate_relay, nonce, "candidate")
        identity = self._remote_identity()
        if (
            identity["installedSha256"] != snapshot["relayCandidateSha256"]
            or identity["runningSha256"] != snapshot["relayCandidateSha256"]
            or snapshot["relayRevision"] not in identity["version"]
        ):
            raise IncompleteEvidence("candidate_installed_or_running_identity_mismatch")
        _write_json_atomic(
            self.paths.restoration,
            {
                "schema": RESTORATION_SCHEMA,
                "status": "candidate_active",
                "ownerRunId": CAMPAIGN_OWNER,
                "deploymentReceiptSha256": receipt["sha256"],
                "candidateRelaySha256": snapshot["relayCandidateSha256"],
                "candidateManifestSha256": receipt["candidateManifestSha256"],
                "priorRelaySha256": authority["priorRelaySha256"],
                "priorManifestSha256": authority["priorManifestSha256"],
            },
            private=True,
        )

    def _restore(self, authority: Mapping[str, Any], *, nonce: str) -> None:
        prior_relay_sha = authority["priorRelaySha256"]
        prior_manifest_sha = authority["priorManifestSha256"]
        candidate_sha = (
            _sha256_file(self.paths.candidate_relay)
            if self.paths.candidate_relay.is_file()
            else None
        )
        identity = self._remote_identity()
        if not (
            identity["installedSha256"] == prior_relay_sha
            and identity["runningSha256"] == prior_relay_sha
        ):
            known = {prior_relay_sha}
            if candidate_sha is not None:
                known.add(candidate_sha)
            if (
                identity["installedSha256"] not in known
                or identity["runningSha256"] not in known
                or not self.paths.prior_relay.is_file()
                or _sha256_file(self.paths.prior_relay) != prior_relay_sha
            ):
                raise IncompleteEvidence("remote_restore_identity_unjoinable")
            self._install_remote_binary(self.paths.prior_relay, nonce, "restore")

        current_manifest_sha = _sha256_file(self.staging_manifest)
        if current_manifest_sha != prior_manifest_sha:
            candidate_manifest_sha = (
                _sha256_file(self.paths.candidate_manifest)
                if self.paths.candidate_manifest.is_file()
                else None
            )
            if (
                current_manifest_sha != candidate_manifest_sha
                or not self.paths.prior_manifest.is_file()
                or _sha256_file(self.paths.prior_manifest) != prior_manifest_sha
            ):
                raise IncompleteEvidence("manifest_restore_sha_cas_failed")
            _event("remote_mutation:manifest_restore")
            self._replace_manifest(current_manifest_sha, self.paths.prior_manifest)

        final_identity = self._remote_identity()
        if (
            final_identity["installedSha256"] != prior_relay_sha
            or final_identity["runningSha256"] != prior_relay_sha
            or _sha256_file(self.staging_manifest) != prior_manifest_sha
        ):
            raise IncompleteEvidence("verified_restoration_failed")
        _write_json_atomic(
            self.paths.restoration,
            {
                "schema": RESTORATION_SCHEMA,
                "status": "restored",
                "ownerRunId": CAMPAIGN_OWNER,
                "priorRelaySha256": prior_relay_sha,
                "priorManifestSha256": prior_manifest_sha,
            },
            private=True,
        )
        self.restored = True
        _event("restored")

    def _revalidate_prepared(
        self, snapshot: Mapping[str, Any], receipt: Mapping[str, Any]
    ) -> None:
        if self._source_digest() != snapshot.get("suiteSourceDigest"):
            raise IncompleteEvidence("suite_source_changed_before_send_claim")
        retained_android = self._retained_profile_binding(
            self.paths.android_report,
            self.paths.android_attestation,
            "android.production_fcm",
        )
        retained_ios = self._retained_profile_binding(
            self.paths.ios_report,
            self.paths.ios_attestation,
            "ios.device.production",
        )
        retained_ios_setup = self._retained_setup_binding(
            str(snapshot.get("suiteSourceDigest", ""))
        )
        for retained, expected, label in (
            (retained_android, snapshot.get("android"), "android"),
            (retained_ios, snapshot.get("ios"), "ios"),
            (retained_ios_setup, snapshot.get("iosSetup"), "ios_setup"),
        ):
            redacted = {key: value for key, value in retained.items() if key != "artifactPath"}
            if redacted != expected:
                raise IncompleteEvidence(f"{label}_binding_changed_before_send_claim")
        if (
            _sha256_file(self.paths.candidate_relay)
            != snapshot.get("relayCandidateSha256")
            or _sha256_file(self.paths.receipt) != receipt.get("sha256")
            or _sha256_file(self.paths.snapshot) != snapshot.get("sha256")
        ):
            raise IncompleteEvidence("retained_deployment_binding_changed")

    def _write_lease(
        self, snapshot: Mapping[str, Any], receipt: Mapping[str, Any], nonce: str
    ) -> None:
        lease = {
            "schema": LEASE_SCHEMA,
            "phase": "ready_to_claim",
            "ownerRunId": CAMPAIGN_OWNER,
            "nonce": nonce,
            "coordinatorPid": os.getpid(),
            "preparedSnapshotSha256": snapshot["sha256"],
            "deploymentReceiptSha256": receipt["sha256"],
            "suiteSourceDigest": snapshot["suiteSourceDigest"],
            "candidateRelaySha256": snapshot["relayCandidateSha256"],
            "candidateRelayRevision": snapshot["relayRevision"],
        }
        _write_json_atomic(self.paths.lease, lease, private=True)

    def _runner_command(self, snapshot: Mapping[str, Any]) -> list[str]:
        dart = _command_from_environment("PLAN398_DART_COMMAND", ["dart"])
        return [
            *dart,
            "run",
            "integration_test/scripts/run_group_reaction_notification_device.dart",
            "--scenario",
            SCENARIO,
            "--diagnostic-only-message-window",
            "--no-child-builds",
            "--sender",
            self.args.sender,
            "--recipient",
            self.args.recipient,
            "--artifact-dir",
            str(self.paths.artifact_directory),
            "--staging-manifest",
            str(self.staging_manifest),
            "--relay-target",
            self.relay_target,
            "--relay-key",
            str(self.relay_key),
            "--service-account",
            str(self.service_account),
            "--prebuilt-android-apk",
            str(snapshot["androidArtifactPath"]),
            "--prebuilt-android-build-report",
            str(self.paths.android_report),
            "--prebuilt-ios-bundle",
            str(snapshot["iosArtifactPath"]),
            "--prebuilt-ios-build-report",
            str(self.paths.ios_report),
            "--prebuilt-ios-setup-app",
            str(snapshot["iosSetupArtifactPath"]),
            "--prebuilt-ios-setup-app-sha256",
            str(snapshot["iosSetup"]["applicationSha256"]),
        ]

    def _runner_environment(self, nonce: str) -> dict[str, str]:
        return {
            "PLAN398_PROJECT_ROOT": str(self.project_root),
            "PLAN398_ACTIVE_TRANSACTION_LEASE": str(self.paths.lease),
            "PLAN398_TRANSACTION_NONCE": nonce,
            "PLAN398_COORDINATOR_PID": str(os.getpid()),
            "PLAN398_DEPLOYMENT_RECEIPT": str(self.paths.receipt),
            "PLAN398_DIAGNOSTIC_ATTEMPT_MARKER": str(self.paths.claim),
            "PLAN398_RELAY_TARGET": self.relay_target,
            "PLAN398_RELAY_KEY": str(self.relay_key),
            "MKNOON_RELAY_ADDRESSES": self.args.relay_addresses,
        }

    def _archive_preclaim_capture_residue(self) -> None:
        source = self.paths.artifact_directory
        if not source.exists():
            return
        if source.is_symlink() or not source.is_dir():
            raise IncompleteEvidence("preclaim_capture_residue_invalid")
        try:
            has_residue = next(source.iterdir(), None) is not None
        except OSError as error:
            raise IncompleteEvidence("preclaim_capture_residue_unreadable") from error
        if not has_residue:
            return
        if self.paths.claim.exists() or self.paths.artifact.exists():
            raise IncompleteEvidence("preclaim_capture_archive_state_invalid")

        archive_root = self.paths.preclaim_attempts
        if archive_root.exists() and (
            archive_root.is_symlink() or not archive_root.is_dir()
        ):
            raise IncompleteEvidence("preclaim_capture_archive_root_invalid")
        archive_root.mkdir(parents=True, exist_ok=True)
        _fsync_directory(archive_root.parent)

        destination: Path | None = None
        receipt: Path | None = None
        ordinal = 0
        for candidate_ordinal in range(1, 1000):
            candidate = archive_root / f"attempt-{candidate_ordinal:03d}"
            candidate_receipt = archive_root / f"attempt-{candidate_ordinal:03d}.json"
            if not candidate.exists() and not candidate_receipt.exists():
                destination = candidate
                receipt = candidate_receipt
                ordinal = candidate_ordinal
                break
        if destination is None or receipt is None:
            raise IncompleteEvidence("preclaim_capture_archive_exhausted")

        try:
            os.replace(source, destination)
        except OSError as error:
            raise IncompleteEvidence("preclaim_capture_archive_move_failed") from error
        _fsync_directory(source.parent)
        _fsync_directory(archive_root)
        payload = {
            "schema": PRECLAIM_ARCHIVE_SCHEMA,
            "ownerRunId": CAMPAIGN_OWNER,
            "archiveOrdinal": ordinal,
            "evidenceRelativePath": destination.relative_to(
                self.paths.campaign
            ).as_posix(),
            "artifactEntitySha256": _entity_digest(destination),
            "authoritativeArtifactPresent": False,
        }
        _write_json_atomic(receipt, payload, private=False)
        _event("preclaim_capture_archived")

    def _start_runner(self, snapshot: Mapping[str, Any], nonce: str) -> int:
        environment = os.environ.copy()
        environment.update(self._runner_environment(nonce))
        _event("runner_start")
        try:
            self.child = subprocess.Popen(
                self._runner_command(snapshot),
                cwd=self.project_root,
                env=environment,
                text=True,
                start_new_session=True,
            )
        except OSError as error:
            raise IncompleteEvidence("device_runner_launch_failed") from error
        return self.child.wait()

    def _revoke_lease_and_stop_child(self) -> None:
        if self.paths.lease.exists():
            try:
                lease = _read_json(self.paths.lease, "active_lease_invalid")
                lease["phase"] = "revoked"
                _write_json_atomic(self.paths.lease, lease, private=True)
            finally:
                self.paths.lease.unlink(missing_ok=True)
                _fsync_directory(self.paths.lease.parent)
        _event("lease_revoked")
        child = self.child
        if child is not None and child.poll() is None:
            try:
                os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                child.wait(timeout=10)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                child.wait(timeout=10)
        _event("runner_awaited")

    def _validate_standalone(self) -> None:
        if not self.paths.artifact.is_file():
            raise IncompleteEvidence("diagnostic_artifact_missing_after_capture")
        command = [
            *_command_from_environment("PLAN398_DART_COMMAND", ["dart"]),
            "run",
            "integration_test/scripts/run_group_reaction_notification_device.dart",
            "--scenario",
            SCENARIO,
            "--validate-artifacts",
            str(self.paths.artifact_directory),
        ]
        _event("standalone_validation")
        _run_command(
            command,
            cwd=self.project_root,
            environment={
                "PLAN398_DEPLOYMENT_RECEIPT": str(self.paths.receipt),
                "PLAN398_DIAGNOSTIC_ATTEMPT_MARKER": str(self.paths.claim),
            },
            code="standalone_diagnostic_validation",
            capture=False,
        )

    def _artifact_matches_claim(self) -> bool:
        try:
            claim = _read_json(self.paths.claim, "claim_invalid")
            receipt = _read_json(self.paths.receipt, "receipt_invalid")
            snapshot = _read_json(self.paths.snapshot, "snapshot_invalid")
            artifact = _read_json(self.paths.artifact, "artifact_invalid")
            _require_private(self.paths.claim, "claim_not_private")
            _require_private(self.paths.receipt, "receipt_not_private")
            if (
                claim.get("schema") != CLAIM_SCHEMA
                or claim.get("ownerRunId") != CAMPAIGN_OWNER
                or receipt.get("schema") != RECEIPT_SCHEMA
                or receipt.get("ownerRunId") != CAMPAIGN_OWNER
                or receipt.get("singleOwnerDeclared") is not True
                or snapshot.get("schema") != SNAPSHOT_SCHEMA
                or artifact.get("schema") != DIAGNOSTIC_ARTIFACT_SCHEMA
                or artifact.get("status") != "diagnostic_complete"
                or artifact.get("diagnosticOnlyMessageWindow") is not True
                or artifact.get("closurePassed") is not False
                or artifact.get("singleOwnerDeclared") is not True
                or artifact.get("diagnosticAttemptClaimed") is not True
            ):
                return False
            claim_sha = _sha256_file(self.paths.claim)
            receipt_sha = _sha256_file(self.paths.receipt)
            snapshot_sha = _sha256_file(self.paths.snapshot)
            if (
                artifact.get("diagnosticAttemptClaimSha256") != claim_sha
                or artifact.get("stagingDeploymentReceiptSha256") != receipt_sha
                or claim.get("deploymentReceiptSha256") != receipt_sha
                or claim.get("preparedSnapshotSha256") != snapshot_sha
                or claim.get("candidateRelaySha256")
                != receipt.get("candidateRelaySha256")
                or claim.get("suiteSourceDigest") != receipt.get("suiteSourceDigest")
            ):
                return False
            build_inputs = artifact.get("buildInputs")
            if not isinstance(build_inputs, dict):
                return False
            mobile_inputs_match = all(
                (
                    build_inputs.get(f"{prefix}ProfileId")
                    == snapshot[prefix]["profileId"]
                    and build_inputs.get(f"{prefix}InputDigest")
                    == snapshot[prefix]["inputDigest"]
                    and build_inputs.get(f"{prefix}ArtifactDigest")
                    == snapshot[prefix]["artifactDigest"]
                )
                for prefix in ("android", "ios")
            )
            setup = snapshot.get("iosSetup")
            return (
                mobile_inputs_match
                and isinstance(setup, dict)
                and receipt.get("iosSetup") == setup
                and build_inputs.get("setupProfileId") == setup.get("profileId")
                and build_inputs.get("setupApplicationSha256")
                == setup.get("applicationSha256")
                and build_inputs.get("setupPreparationCompileCommands")
                == setup.get("centralCompileCommands")
                and build_inputs.get("captureChildBuildCount")
                == setup.get("childBuildCount")
            )
        except (IncompleteEvidence, KeyError, TypeError):
            return False

    def _handle_claim_present(self, authority: Mapping[str, Any]) -> int:
        nonce = os.urandom(12).hex()
        self._restore(authority, nonce=nonce)
        if not self.paths.artifact.is_file() or not self._artifact_matches_claim():
            raise IncompleteEvidence("claimed_campaign_artifact_absent_incomplete_or_mismatched")
        self._validate_standalone()
        print("DIAGNOSTIC_COMPLETE: retained Plan 398 artifact validated after restoration.")
        return 0

    def run(self) -> int:
        self.validate_static_inputs()
        lock = self.acquire_lock()
        authority: dict[str, Any] | None = None
        recovery_nonce = os.urandom(16).hex()
        try:
            authority = self._prior_authority()
            claim_present = self.paths.claim.exists()
            artifact_present = self.paths.artifact.exists()
            if not claim_present and artifact_present:
                raise IncompleteEvidence("unclaimed_diagnostic_artifact_present")
            if claim_present:
                return self._handle_claim_present(authority)
            if self.args.run_id != CAMPAIGN_OWNER:
                raise IncompleteEvidence("fresh_campaign_requires_fixed_diagnostic_owner")

            self._archive_preclaim_capture_residue()
            snapshot = self._prepare_and_retain()
            receipt = self._prepare_deployment_receipt(snapshot, authority)
            nonce = os.urandom(16).hex()
            if self.paths.restoration.exists():
                state = _read_json(self.paths.restoration, "restoration_state_invalid")
                if state.get("status") != "restored":
                    self._restore(authority, nonce=nonce)
            self._deploy(snapshot, receipt, authority, nonce)
            self._revalidate_prepared(snapshot, receipt)
            self._write_lease(snapshot, receipt, nonce)

            runner_status: int | None = None
            primary_error: BaseException | None = None
            try:
                runner_status = self._start_runner(snapshot, nonce)
                if self._signal is not None:
                    raise InterruptedTransaction(self._signal)
            except BaseException as error:  # cleanup must cover signals, too
                primary_error = error
            restoration_error: BaseException | None = None
            try:
                self._revoke_lease_and_stop_child()
                self._restore(authority, nonce=nonce)
            except BaseException as error:
                restoration_error = error

            validation_error: BaseException | None = None
            if restoration_error is None and self.paths.artifact.is_file():
                try:
                    self._validate_standalone()
                except BaseException as error:
                    validation_error = error

            if restoration_error is not None:
                raise restoration_error
            if primary_error is not None:
                raise primary_error
            if runner_status != 0:
                raise IncompleteEvidence(f"diagnostic_runner_failed_{runner_status}")
            if validation_error is not None:
                raise validation_error
            if not self._artifact_matches_claim():
                raise IncompleteEvidence("diagnostic_artifact_claim_binding_invalid")
            print("DIAGNOSTIC_COMPLETE: one Plan 398 message window sealed and restored.")
            return 0
        finally:
            try:
                if self.deployed and not self.restored and authority is not None:
                    self._revoke_lease_and_stop_child()
                    self._restore(authority, nonce=recovery_nonce)
            finally:
                lock.close()

    def install_signal_handlers(self) -> None:
        def handle(signum: int, _frame: Any) -> None:
            self._signal = signum
            raise InterruptedTransaction(signum)

        for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(signum, handle)


class ManualTraceTransaction(Transaction):
    """Run one user-authored installed-state send under relay-only rollback."""

    def __init__(self, args: argparse.Namespace) -> None:
        super().__init__(args)
        self.live_diagnostic = args.live_diagnostic
        self.attempt_namespace = args.attempt_namespace
        self.authorized_retry_requested = self.attempt_namespace is not None
        self.artifact_directory_argument = Path(args.artifact_dir).absolute()
        self.artifact_directory = self.artifact_directory_argument.resolve()
        self.authority_artifact_directory = (
            self.project_root / FINAL_RUNNER_ARTIFACT_RELATIVE
        ).resolve()
        self.group_name = args.group_name
        self.existing_target_marker = args.existing_target_marker
        self.expected_failure_sha256 = (
            None
            if self.live_diagnostic
            else _require_sha(
                args.retained_failure_sha256,
                "manual_trace_retained_failure_sha_invalid",
            )
        )
        self.trace_artifact = self.artifact_directory / TRACE_ARTIFACT_NAME
        self.trace_claim = self.artifact_directory / TRACE_CLAIM_NAME
        self.trace_failure = self.artifact_directory / TRACE_FAILURE_NAME
        self.trace_manifest = self.artifact_directory / TRACE_MANIFEST_NAME
        self.trace_relay_state = self.artifact_directory / TRACE_RELAY_STATE_NAME
        self.trace_terminal_receipt = (
            self.artifact_directory / TRACE_TERMINAL_RECEIPT_NAME
        )
        self.authorized_retry_terminal_receipt = (
            self.artifact_directory / TRACE_AUTHORIZED_RETRY_RECEIPT_NAME
        )
        self.prior_manual_preclaim_journal = (
            self.artifact_directory / "plan398_existing_state_trace_command_journal.json"
        )
        self.prior_manual_preclaim_device_log = (
            self.artifact_directory / f"device_logcat_{self.args.sender}.log"
        )
        self.prior_manual_preclaim_archive = (
            self.artifact_directory / "preclaim-attempts" / "attempt-01"
        )
        self.prior_manual_preclaim_receipt = (
            self.prior_manual_preclaim_archive / "receipt.json"
        )
        self.prior_manual_preclaim_hashes = {
            "journalSha256": args.prior_manual_preclaim_journal_sha256,
            "deviceLogSha256": args.prior_manual_preclaim_device_log_sha256,
            "traceManifestSha256": (
                args.prior_manual_preclaim_trace_manifest_sha256
            ),
            "traceRelayStateSha256": (
                args.prior_manual_preclaim_trace_relay_state_sha256
            ),
        }
        self.final_attempt_authorization_id = (
            args.final_attempt_authorization_id
        )
        self.final_attempt_hashes = {
            "journalSha256": args.final_attempt_journal_sha256,
            "deviceLogSha256": args.final_attempt_device_log_sha256,
            "traceManifestSha256": args.final_attempt_trace_manifest_sha256,
            "traceRelayStateSha256": (
                args.final_attempt_trace_relay_state_sha256
            ),
        }
        self.final_attempt_02_archive = (
            self.artifact_directory / "preclaim-attempts" / "attempt-02"
        )
        self.final_attempt_02_receipt = (
            self.final_attempt_02_archive / "receipt.json"
        )
        self.final_runner_product_receipt_sha256 = (
            args.plan398_final_runner_product_receipt_sha256
        )
        self.final_runner_install_terminal_sha256 = (
            args.plan398_final_runner_install_terminal_sha256
        )
        self.final_attempt_02_receipt_sha256 = (
            args.plan398_attempt_02_receipt_sha256
        )
        self.final_runner_binding: dict[str, str] | None = None

    def _prior_manual_preclaim_sources(self) -> dict[str, Path]:
        return {
            "journalSha256": self.prior_manual_preclaim_journal,
            "deviceLogSha256": self.prior_manual_preclaim_device_log,
            "traceManifestSha256": self.trace_manifest,
            "traceRelayStateSha256": self.trace_relay_state,
        }

    def _prior_manual_preclaim_receipt_payload(
        self, hashes: Mapping[str, str]
    ) -> dict[str, Any]:
        return {
            "schema": MANUAL_PRECLAIM_ARCHIVE_SCHEMA,
            "attempt": "attempt-01",
            "journalSha256": hashes["journalSha256"],
            "deviceLogSha256": hashes["deviceLogSha256"],
            "traceManifestSha256": hashes["traceManifestSha256"],
            "traceRelayStateSha256": hashes["traceRelayStateSha256"],
        }

    def _validate_and_read_prior_manual_preclaim_sources(
        self,
    ) -> tuple[dict[str, str], dict[str, bytes]]:
        sources = self._prior_manual_preclaim_sources()
        for key, source in sources.items():
            if source.is_symlink() or not source.is_file():
                raise IncompleteEvidence(f"manual_trace_prior_manual_preclaim_{key}_invalid")
            _require_private(
                source,
                f"manual_trace_prior_manual_preclaim_{key}_not_private",
            )

        hashes: dict[str, str] = {}
        payloads: dict[str, bytes] = {}
        for key, source in sources.items():
            try:
                payload = source.read_bytes()
            except OSError as error:
                raise IncompleteEvidence(
                    f"manual_trace_prior_manual_preclaim_{key}_unreadable"
                ) from error
            digest = _sha256_bytes(payload)
            expected = self.prior_manual_preclaim_hashes[key]
            if digest != expected:
                raise IncompleteEvidence(
                    f"manual_trace_prior_manual_preclaim_{key}_changed"
                )
            hashes[key] = digest
            payloads[key] = payload
        return hashes, payloads

    def _archive_prior_manual_preclaim_evidence(self) -> None:
        """Seal prior manual evidence before anything can overwrite its trace."""

        sources = self._prior_manual_preclaim_sources()
        source_evidence_present = any(
            _path_present(path) for path in sources.values()
        )
        recovery_args_present = any(
            value is not None for value in self.prior_manual_preclaim_hashes.values()
        )
        archive_present = _path_present(self.prior_manual_preclaim_archive)
        if (
            not source_evidence_present
            and not recovery_args_present
            and not archive_present
        ):
            return
        if not source_evidence_present:
            raise IncompleteEvidence("manual_trace_prior_manual_preclaim_evidence_missing")
        if not all(
            value is not None for value in self.prior_manual_preclaim_hashes.values()
        ):
            raise IncompleteEvidence("manual_trace_prior_manual_preclaim_hashes_required")
        for key, value in self.prior_manual_preclaim_hashes.items():
            self.prior_manual_preclaim_hashes[key] = _require_sha(
                value, f"manual_trace_prior_manual_preclaim_{key}_sha_invalid"
            )

        hashes, payloads = self._validate_and_read_prior_manual_preclaim_sources()
        receipt_payload = self._prior_manual_preclaim_receipt_payload(hashes)
        archive_root = self.prior_manual_preclaim_archive.parent
        archive_files = {
            key: self.prior_manual_preclaim_archive / source.name
            for key, source in sources.items()
        }
        if archive_present:
            if (
                self.prior_manual_preclaim_archive.is_symlink()
                or not self.prior_manual_preclaim_archive.is_dir()
                or stat.S_IMODE(
                    self.prior_manual_preclaim_archive.stat().st_mode
                )
                != 0o700
            ):
                raise IncompleteEvidence("manual_trace_prior_manual_preclaim_archive_invalid")
            if (
                self.prior_manual_preclaim_receipt.is_symlink()
                or not self.prior_manual_preclaim_receipt.is_file()
            ):
                raise IncompleteEvidence("manual_trace_prior_manual_preclaim_receipt_missing")
            _require_private(
                self.prior_manual_preclaim_receipt,
                "manual_trace_prior_manual_preclaim_receipt_not_private",
            )
            if _read_json(
                self.prior_manual_preclaim_receipt,
                "manual_trace_prior_manual_preclaim_receipt_invalid",
            ) != receipt_payload:
                raise IncompleteEvidence("manual_trace_prior_manual_preclaim_receipt_changed")
            for key, archived in archive_files.items():
                if archived.is_symlink() or not archived.is_file():
                    raise IncompleteEvidence(
                        f"manual_trace_prior_manual_preclaim_archive_{key}_missing"
                    )
                _require_private(
                    archived,
                    f"manual_trace_prior_manual_preclaim_archive_{key}_not_private",
                )
                if _sha256_file(archived) != hashes[key]:
                    raise IncompleteEvidence(
                        f"manual_trace_prior_manual_preclaim_archive_{key}_changed"
                    )
            raise IncompleteEvidence(
                "manual_trace_prior_manual_preclaim_already_archived"
            )

        try:
            if _path_present(archive_root):
                if (
                    archive_root.is_symlink()
                    or not archive_root.is_dir()
                    or stat.S_IMODE(archive_root.stat().st_mode) != 0o700
                ):
                    raise IncompleteEvidence(
                        "manual_trace_prior_manual_preclaim_archive_root_invalid"
                    )
            else:
                archive_root.mkdir(parents=True, mode=0o700)
                os.chmod(archive_root, 0o700)
                _fsync_directory(archive_root.parent)
            self.prior_manual_preclaim_archive.mkdir(mode=0o700)
            os.chmod(self.prior_manual_preclaim_archive, 0o700)
            _fsync_directory(archive_root)
        except IncompleteEvidence:
            raise
        except OSError as error:
            raise IncompleteEvidence(
                "manual_trace_prior_manual_preclaim_archive_create_failed"
            ) from error
        for key, archived in archive_files.items():
            _write_no_replace(
                archived,
                payloads[key],
                private=True,
                code=f"manual_trace_prior_manual_preclaim_archive_{key}_exists",
            )
        _write_no_replace(
            self.prior_manual_preclaim_receipt,
            _canonical_json(receipt_payload),
            private=True,
            code="manual_trace_prior_manual_preclaim_receipt_exists",
        )
        _event("manual_trace_prior_manual_preclaim_archived")

    def _final_attempt_requested(self) -> bool:
        return any(
            value is not None
            for value in (
                self.final_attempt_authorization_id,
                *self.final_attempt_hashes.values(),
            )
        )

    def _runner_binding_requested(self) -> bool:
        return self._final_attempt_requested() or self.authorized_retry_requested

    def _validate_selected_runner_binding(self) -> dict[str, str]:
        return self._validate_final_runner_manual_binding()

    def _final_attempt_sources(self) -> dict[str, Path]:
        return {
            "journalSha256": self.prior_manual_preclaim_journal,
            "deviceLogSha256": (
                self.artifact_directory
                / f"device_logcat_{FINAL_ATTEMPT_PIXEL_ID}.log"
            ),
            "traceManifestSha256": self.trace_manifest,
            "traceRelayStateSha256": self.trace_relay_state,
        }

    @staticmethod
    def _read_descriptor(descriptor: int) -> bytes:
        os.lseek(descriptor, 0, os.SEEK_SET)
        chunks: list[bytes] = []
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                return b"".join(chunks)
            chunks.append(chunk)

    @staticmethod
    def _regular_lstat(path: Path, code: str) -> os.stat_result:
        try:
            metadata = path.lstat()
        except OSError as error:
            raise IncompleteEvidence(code) from error
        if not stat.S_ISREG(metadata.st_mode):
            raise IncompleteEvidence(code)
        return metadata

    def _validate_fixed_attempt_01(self) -> str:
        archive = self.prior_manual_preclaim_archive
        archive_root = archive.parent
        for directory, code in (
            (archive_root, "manual_trace_final_attempt_archive_root_invalid"),
            (archive, "manual_trace_final_attempt_01_invalid"),
        ):
            if directory.is_symlink() or not directory.is_dir():
                raise IncompleteEvidence(code)
            try:
                mode = stat.S_IMODE(directory.stat().st_mode)
            except OSError as error:
                raise IncompleteEvidence(code) from error
            if mode != 0o700:
                raise IncompleteEvidence(code)

        expected_receipt = {
            "schema": MANUAL_PRECLAIM_ARCHIVE_SCHEMA,
            "attempt": "attempt-01",
            "journalSha256": FINAL_ATTEMPT_01_HASHES["journalSha256"],
            "deviceLogSha256": FINAL_ATTEMPT_01_HASHES["deviceLogSha256"],
            "traceManifestSha256": FINAL_ATTEMPT_01_HASHES[
                "traceManifestSha256"
            ],
            "traceRelayStateSha256": FINAL_ATTEMPT_01_HASHES[
                "traceRelayStateSha256"
            ],
        }
        receipt = self.prior_manual_preclaim_receipt
        receipt_stat = self._regular_lstat(
            receipt,
            "manual_trace_final_attempt_01_receipt_invalid",
        )
        if (
            stat.S_IMODE(receipt_stat.st_mode) != 0o600
            or receipt_stat.st_nlink != 1
        ):
            raise IncompleteEvidence(
                "manual_trace_final_attempt_01_receipt_not_private"
            )
        try:
            receipt_bytes = receipt.read_bytes()
        except OSError as error:
            raise IncompleteEvidence(
                "manual_trace_final_attempt_01_receipt_unreadable"
            ) from error
        if (
            _sha256_bytes(receipt_bytes) != FINAL_ATTEMPT_01_RECEIPT_SHA256
            or receipt_bytes != _canonical_json(expected_receipt)
            or _read_json(
                receipt,
                "manual_trace_final_attempt_01_receipt_invalid",
            )
            != expected_receipt
        ):
            raise IncompleteEvidence(
                "manual_trace_final_attempt_01_receipt_changed"
            )

        member_paths = {
            "journalSha256": archive
            / self.prior_manual_preclaim_journal.name,
            "deviceLogSha256": archive
            / f"device_logcat_{FINAL_ATTEMPT_PIXEL_ID}.log",
            "traceManifestSha256": archive / self.trace_manifest.name,
            "traceRelayStateSha256": archive / self.trace_relay_state.name,
        }
        expected_names = {
            receipt.name,
            *(path.name for path in member_paths.values()),
        }
        try:
            actual_names = {entry.name for entry in archive.iterdir()}
        except OSError as error:
            raise IncompleteEvidence(
                "manual_trace_final_attempt_01_entity_unreadable"
            ) from error
        if actual_names != expected_names:
            raise IncompleteEvidence(
                "manual_trace_final_attempt_01_entity_changed"
            )

        identities = {(receipt_stat.st_dev, receipt_stat.st_ino)}
        for key, member in member_paths.items():
            member_stat = self._regular_lstat(
                member,
                f"manual_trace_final_attempt_01_{key}_invalid",
            )
            identity = (member_stat.st_dev, member_stat.st_ino)
            if identity in identities or member_stat.st_nlink != 1:
                raise IncompleteEvidence(
                    "manual_trace_final_attempt_01_entity_not_distinct"
                )
            identities.add(identity)
            if stat.S_IMODE(member_stat.st_mode) != 0o600:
                raise IncompleteEvidence(
                    f"manual_trace_final_attempt_01_{key}_not_private"
                )
            if _sha256_file(member) != FINAL_ATTEMPT_01_HASHES[key]:
                raise IncompleteEvidence(
                    f"manual_trace_final_attempt_01_{key}_changed"
                )
        return _entity_digest(archive)

    def _preflight_final_attempt_02_archive(self) -> None:
        archive_root = self.final_attempt_02_archive.parent
        if (
            archive_root.is_symlink()
            or not archive_root.is_dir()
            or stat.S_IMODE(archive_root.stat().st_mode) != 0o700
        ):
            raise IncompleteEvidence(
                "manual_trace_final_attempt_archive_root_invalid"
            )
        if _path_present(self.final_attempt_02_archive):
            raise IncompleteEvidence(
                "manual_trace_final_attempt_02_archive_collision"
            )

    def _read_final_attempt_sources(
        self,
        *,
        device_mode: int,
    ) -> tuple[dict[str, bytes], dict[str, tuple[int, int]]]:
        sources = self._final_attempt_sources()
        payloads: dict[str, bytes] = {}
        identities: dict[str, tuple[int, int]] = {}
        observed_identities: set[tuple[int, int]] = set()
        flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0)
        flags |= getattr(os, "O_NOFOLLOW", 0)
        for key, source in sources.items():
            path_stat = self._regular_lstat(
                source,
                f"manual_trace_final_attempt_{key}_invalid",
            )
            try:
                descriptor = os.open(source, flags)
            except OSError as error:
                raise IncompleteEvidence(
                    f"manual_trace_final_attempt_{key}_unreadable"
                ) from error
            try:
                descriptor_stat = os.fstat(descriptor)
                identity = (descriptor_stat.st_dev, descriptor_stat.st_ino)
                if (
                    not stat.S_ISREG(descriptor_stat.st_mode)
                    or identity != (path_stat.st_dev, path_stat.st_ino)
                    or identity in observed_identities
                    or descriptor_stat.st_nlink != 1
                ):
                    raise IncompleteEvidence(
                        "manual_trace_final_attempt_sources_not_distinct"
                    )
                mode = stat.S_IMODE(descriptor_stat.st_mode)
                if key == "deviceLogSha256":
                    if mode != device_mode:
                        raise IncompleteEvidence(
                            "manual_trace_final_attempt_device_log_mode_invalid"
                        )
                elif mode != 0o600:
                    raise IncompleteEvidence(
                        f"manual_trace_final_attempt_{key}_mode_invalid"
                    )
                payload = self._read_descriptor(descriptor)
            finally:
                os.close(descriptor)
            digest = _sha256_bytes(payload)
            if digest != self.final_attempt_hashes[key]:
                raise IncompleteEvidence(
                    f"manual_trace_final_attempt_{key}_changed"
                )
            observed_identities.add(identity)
            identities[key] = identity
            payloads[key] = payload
        return payloads, identities

    def _harden_final_attempt_device_log(
        self,
        *,
        expected_payload: bytes,
        expected_identity: tuple[int, int],
    ) -> None:
        device_log = self._final_attempt_sources()["deviceLogSha256"]
        flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0)
        flags |= getattr(os, "O_NOFOLLOW", 0)
        try:
            descriptor = os.open(device_log, flags)
        except OSError as error:
            raise IncompleteEvidence(
                "manual_trace_final_attempt_device_log_unreadable"
            ) from error
        try:
            before = os.fstat(descriptor)
            if (
                not stat.S_ISREG(before.st_mode)
                or (before.st_dev, before.st_ino) != expected_identity
                or before.st_nlink != 1
                or stat.S_IMODE(before.st_mode) != 0o644
            ):
                raise IncompleteEvidence(
                    "manual_trace_final_attempt_device_log_changed_before_hardening"
                )
            before_payload = self._read_descriptor(descriptor)
            if (
                before_payload != expected_payload
                or _sha256_bytes(before_payload)
                != self.final_attempt_hashes["deviceLogSha256"]
            ):
                raise IncompleteEvidence(
                    "manual_trace_final_attempt_device_log_changed_before_hardening"
                )
            os.fchmod(descriptor, 0o600)
            os.fsync(descriptor)
            after = os.fstat(descriptor)
            after_payload = self._read_descriptor(descriptor)
            if (
                (after.st_dev, after.st_ino) != expected_identity
                or stat.S_IMODE(after.st_mode) != 0o600
                or after_payload != expected_payload
                or _sha256_bytes(after_payload)
                != self.final_attempt_hashes["deviceLogSha256"]
            ):
                raise IncompleteEvidence(
                    "manual_trace_final_attempt_device_log_hardening_changed_bytes"
                )
        except OSError as error:
            raise IncompleteEvidence(
                "manual_trace_final_attempt_device_log_hardening_failed"
            ) from error
        finally:
            os.close(descriptor)
        path_stat = self._regular_lstat(
            device_log,
            "manual_trace_final_attempt_device_log_changed_after_hardening",
        )
        if (
            (path_stat.st_dev, path_stat.st_ino) != expected_identity
            or stat.S_IMODE(path_stat.st_mode) != 0o600
            or _sha256_file(device_log)
            != self.final_attempt_hashes["deviceLogSha256"]
        ):
            raise IncompleteEvidence(
                "manual_trace_final_attempt_device_log_changed_after_hardening"
            )
        _fsync_directory(device_log.parent)

    def _validate_final_attempt_02_archive(
        self,
        *,
        sources: Mapping[str, Path],
        payloads: Mapping[str, bytes],
        receipt_payload: Mapping[str, Any],
    ) -> None:
        archive = self.final_attempt_02_archive
        if (
            archive.is_symlink()
            or not archive.is_dir()
            or stat.S_IMODE(archive.stat().st_mode) != 0o700
        ):
            raise IncompleteEvidence(
                "manual_trace_final_attempt_02_archive_invalid"
            )
        archive_files = {
            key: archive / source.name for key, source in sources.items()
        }
        expected_names = {
            self.final_attempt_02_receipt.name,
            *(path.name for path in archive_files.values()),
        }
        try:
            actual_names = {entry.name for entry in archive.iterdir()}
        except OSError as error:
            raise IncompleteEvidence(
                "manual_trace_final_attempt_02_archive_unreadable"
            ) from error
        if actual_names != expected_names:
            raise IncompleteEvidence(
                "manual_trace_final_attempt_02_entity_invalid"
            )
        identities: set[tuple[int, int]] = set()
        for key, archived in archive_files.items():
            archived_stat = self._regular_lstat(
                archived,
                f"manual_trace_final_attempt_02_{key}_invalid",
            )
            identity = (archived_stat.st_dev, archived_stat.st_ino)
            if identity in identities or archived_stat.st_nlink != 1:
                raise IncompleteEvidence(
                    "manual_trace_final_attempt_02_entity_not_distinct"
                )
            identities.add(identity)
            if (
                stat.S_IMODE(archived_stat.st_mode) != 0o600
                or archived.read_bytes() != payloads[key]
                or _sha256_file(archived) != self.final_attempt_hashes[key]
            ):
                raise IncompleteEvidence(
                    f"manual_trace_final_attempt_02_{key}_changed"
                )
        receipt_stat = self._regular_lstat(
            self.final_attempt_02_receipt,
            "manual_trace_final_attempt_02_receipt_invalid",
        )
        if (
            stat.S_IMODE(receipt_stat.st_mode) != 0o600
            or (receipt_stat.st_dev, receipt_stat.st_ino) in identities
            or receipt_stat.st_nlink != 1
            or self.final_attempt_02_receipt.read_bytes()
            != _canonical_json(receipt_payload)
        ):
            raise IncompleteEvidence(
                "manual_trace_final_attempt_02_receipt_invalid"
            )

    def _archive_final_manual_preclaim_evidence(self) -> None:
        """Consume one reviewed attempt-02 archive authority before deploy."""

        attempt_01_entity = self._validate_fixed_attempt_01()
        self._preflight_final_attempt_02_archive()
        sources = self._final_attempt_sources()
        payloads, identities = self._read_final_attempt_sources(
            device_mode=0o644
        )
        if _sha256_file(self.trace_failure) != self.expected_failure_sha256:
            raise IncompleteEvidence("manual_trace_retained_failure_changed")

        try:
            self.final_attempt_02_archive.mkdir(mode=0o700)
            os.chmod(self.final_attempt_02_archive, 0o700)
            _fsync_directory(self.final_attempt_02_archive.parent)
        except OSError as error:
            raise IncompleteEvidence(
                "manual_trace_final_attempt_02_archive_create_failed"
            ) from error

        self._harden_final_attempt_device_log(
            expected_payload=payloads["deviceLogSha256"],
            expected_identity=identities["deviceLogSha256"],
        )
        hardened_payloads, hardened_identities = self._read_final_attempt_sources(
            device_mode=0o600
        )
        if hardened_payloads != payloads or hardened_identities != identities:
            raise IncompleteEvidence(
                "manual_trace_final_attempt_sources_changed_during_hardening"
            )

        archive_files = {
            key: self.final_attempt_02_archive / source.name
            for key, source in sources.items()
        }
        for key, archived in archive_files.items():
            _write_no_replace(
                archived,
                payloads[key],
                private=True,
                code=f"manual_trace_final_attempt_02_{key}_collision",
            )
        receipt_payload = {
            "schema": FINAL_MANUAL_PRECLAIM_ARCHIVE_SCHEMA,
            "attempt": "attempt-02",
            "authorizationId": self.final_attempt_authorization_id,
            "priorAttempt": "attempt-01",
            "priorAttemptReceiptSha256": FINAL_ATTEMPT_01_RECEIPT_SHA256,
            "priorAttemptEntitySha256": attempt_01_entity,
            "journalSha256": self.final_attempt_hashes["journalSha256"],
            "deviceLogSha256": self.final_attempt_hashes["deviceLogSha256"],
            "traceManifestSha256": self.final_attempt_hashes[
                "traceManifestSha256"
            ],
            "traceRelayStateSha256": self.final_attempt_hashes[
                "traceRelayStateSha256"
            ],
        }
        _write_no_replace(
            self.final_attempt_02_receipt,
            _canonical_json(receipt_payload),
            private=True,
            code="manual_trace_final_attempt_02_receipt_collision",
        )
        self._validate_final_attempt_02_archive(
            sources=sources,
            payloads=payloads,
            receipt_payload=receipt_payload,
        )
        if self._validate_fixed_attempt_01() != attempt_01_entity:
            raise IncompleteEvidence(
                "manual_trace_final_attempt_01_entity_changed"
            )
        if _sha256_file(self.trace_failure) != self.expected_failure_sha256:
            raise IncompleteEvidence("manual_trace_retained_failure_changed")
        _event("manual_trace_final_attempt_archived")

    def _validate_final_runner_manual_binding(self) -> dict[str, str]:
        """Revalidate the sealed update and attempt-02 immediately before use."""

        retry_authority_before: dict[str, Any] | None = None
        authority_artifact = self.artifact_directory
        namespace_name = FINAL_RUNNER_NAMESPACE_NAME
        expected_authorization = FINAL_ATTEMPT_AUTHORIZATION
        expected_product_relative = "build/ios/iphoneos/Runner.app"
        if self.authorized_retry_requested:
            authority_artifact = self.authority_artifact_directory
            namespace_name = FINAL_RUNNER_AUTHORIZED_RETRY_NAMESPACE_NAME
            expected_authorization = (
                FINAL_RUNNER_AUTHORIZED_RETRY_AUTHORIZATION
            )
            expected_product_relative = (
                FINAL_RUNNER_ARTIFACT_RELATIVE
                / FINAL_RUNNER_AUTHORIZED_RETRY_NAMESPACE_NAME
                / FINAL_RUNNER_AUTHORIZED_RETRY_PRODUCT_NAME
            ).as_posix()
            retry_authority_before = _validate_authorized_retry_authority(
                authority_artifact
            )
            evidence = retry_authority_before["evidence"]
        else:
            evidence = _validate_fixed_final_attempt_evidence(
                authority_artifact
            )
        attempt_02_receipt = (
            authority_artifact
            / "preclaim-attempts"
            / "attempt-02"
            / "receipt.json"
        )
        _require_private_regular(
            attempt_02_receipt,
            "manual_trace_final_attempt_02_receipt_invalid",
        )
        attempt_02_sha = _sha256_file(attempt_02_receipt)
        if attempt_02_sha != self.final_attempt_02_receipt_sha256:
            raise IncompleteEvidence(
                "manual_trace_final_attempt_02_receipt_hash_changed"
            )

        namespace = authority_artifact / namespace_name
        if (
            namespace.is_symlink()
            or not namespace.is_dir()
            or stat.S_IMODE(namespace.stat().st_mode) != 0o700
        ):
            raise IncompleteEvidence("manual_trace_final_runner_namespace_invalid")
        paths = {
            "buildClaim": namespace / FINAL_RUNNER_BUILD_CLAIM_NAME,
            "buildReceipt": namespace / FINAL_RUNNER_BUILD_RECEIPT_NAME,
            "installClaim": namespace / FINAL_RUNNER_INSTALL_CLAIM_NAME,
            "installReceipt": namespace / FINAL_RUNNER_INSTALL_RECEIPT_NAME,
        }
        try:
            expected_names = {path.name for path in paths.values()}
            if self.authorized_retry_requested:
                expected_names.add(
                    FINAL_RUNNER_AUTHORIZED_RETRY_PRODUCT_NAME
                )
            if {entry.name for entry in namespace.iterdir()} != expected_names:
                raise IncompleteEvidence(
                    "manual_trace_final_runner_namespace_entity_invalid"
                )
        except OSError as error:
            raise IncompleteEvidence(
                "manual_trace_final_runner_namespace_unreadable"
            ) from error
        for key, path in paths.items():
            _require_private_regular(
                path, f"manual_trace_final_runner_{key}_invalid"
            )
        build_claim = _read_json(
            paths["buildClaim"], "manual_trace_final_runner_build_claim_invalid"
        )
        build_receipt = _read_json(
            paths["buildReceipt"],
            "manual_trace_final_runner_build_receipt_invalid",
        )
        install_claim = _read_json(
            paths["installClaim"],
            "manual_trace_final_runner_install_claim_invalid",
        )
        install_receipt = _read_json(
            paths["installReceipt"],
            "manual_trace_final_runner_install_receipt_invalid",
        )
        build_receipt_sha = _sha256_file(paths["buildReceipt"])
        install_receipt_sha = _sha256_file(paths["installReceipt"])
        if (
            build_receipt_sha != self.final_runner_product_receipt_sha256
            or install_receipt_sha
            != self.final_runner_install_terminal_sha256
        ):
            raise IncompleteEvidence(
                "manual_trace_final_runner_receipt_hash_changed"
            )

        product = build_receipt.get("product")
        if not isinstance(product, dict):
            raise IncompleteEvidence(
                "manual_trace_final_runner_product_binding_invalid"
            )
        build_name = build_receipt.get("buildName")
        build_number = build_receipt.get("buildNumber")
        expected_build_argv = [
            "flutter",
            "build",
            "ios",
            "--release",
            "--target=lib/main.dart",
            "--dart-define=PRODUCTION_APNS=true",
            f"--build-name={build_name}",
            f"--build-number={build_number}",
        ]
        if (
            build_claim.get("schema") != FINAL_RUNNER_BUILD_CLAIM_SCHEMA
            or build_receipt.get("schema")
            != FINAL_RUNNER_BUILD_RECEIPT_SCHEMA
            or build_receipt.get("status") != "succeeded"
            or build_receipt.get("claimSha256")
            != _sha256_file(paths["buildClaim"])
            or build_claim.get("authorizationId")
            != expected_authorization
            or build_receipt.get("authorizationId")
            != expected_authorization
            or build_claim.get("recipient") != FINAL_RUNNER_RECIPIENT
            or build_receipt.get("recipient") != FINAL_RUNNER_RECIPIENT
            or build_claim.get("bundleIdentifier") != FINAL_RUNNER_BUNDLE_ID
            or build_receipt.get("bundleIdentifier")
            != FINAL_RUNNER_BUNDLE_ID
            or build_claim.get("evidence") != evidence
            or build_receipt.get("evidence") != evidence
            or build_receipt.get("configuration") != "Release"
            or build_claim.get("configuration") != "Release"
            or not isinstance(build_name, str)
            or re.fullmatch(r"[0-9]+(?:\.[0-9]+){2}", build_name) is None
            or not isinstance(build_number, str)
            or re.fullmatch(r"[1-9][0-9]{0,17}", build_number) is None
            or build_claim.get("buildName") != build_name
            or build_claim.get("buildNumber") != build_number
            or build_claim.get("buildArgv") != expected_build_argv
            or build_receipt.get("buildArgv") != expected_build_argv
            or product.get("bundleShortVersion") != build_name
            or product.get("bundleVersion") != build_number
            or build_claim.get("xcodeBuildSettings")
            != FINAL_RUNNER_XCODE_BUILD_SETTINGS
            or build_receipt.get("xcodeBuildSettings")
            != FINAL_RUNNER_XCODE_BUILD_SETTINGS
            or build_receipt.get("suiteSourceDigestBefore")
            != build_receipt.get("suiteSourceDigestAfter")
        ):
            raise IncompleteEvidence(
                "manual_trace_final_runner_build_receipt_binding_invalid"
            )
        sealed_source_digest = _require_sha(
            build_receipt.get("suiteSourceDigestBefore"),
            "manual_trace_final_runner_source_digest_invalid",
        )
        if _suite_source_digest(self.project_root) != sealed_source_digest:
            raise IncompleteEvidence(
                "manual_trace_final_runner_source_changed_after_install"
            )
        for key in (
            "entitySha256",
            "applicationSha256",
            "runnerExecutableSha256",
            "infoPlistSha256",
            "canonicalSignedEntitlementsSha256",
            "embeddedMobileProvisionSha256",
        ):
            _require_sha(
                product.get(key),
                f"manual_trace_final_runner_product_{key}_invalid",
            )
        team = product.get("signedTeamIdentifier")
        certificates = product.get("developerCertificateSha256")
        if (
            product.get("relativePath") != expected_product_relative
            or product.get("bundleIdentifier") != FINAL_RUNNER_BUNDLE_ID
            or product.get("executableName") != "Runner"
            or product.get("configuration") != "Release"
            or product.get("signedIdentifier") != FINAL_RUNNER_BUNDLE_ID
            or not isinstance(team, str)
            or re.fullmatch(r"[A-Z0-9]{10}", team) is None
            or product.get("profileTeamIdentifier") != team
            or product.get("profileApplicationIdentifier")
            != f"{team}.{FINAL_RUNNER_BUNDLE_ID}"
            or not isinstance(product.get("bundleShortVersion"), str)
            or not product.get("bundleShortVersion")
            or not isinstance(product.get("bundleVersion"), str)
            or not product.get("bundleVersion")
            or not isinstance(product.get("profileExpirationUtc"), str)
            or not product.get("profileExpirationUtc").endswith("Z")
            or not isinstance(certificates, list)
            or not certificates
        ):
            raise IncompleteEvidence(
                "manual_trace_final_runner_product_binding_invalid"
            )
        for value in certificates:
            _require_sha(
                value, "manual_trace_final_runner_developer_certificate_invalid"
            )

        if (
            install_claim.get("schema") != FINAL_RUNNER_INSTALL_CLAIM_SCHEMA
            or install_receipt.get("schema")
            != FINAL_RUNNER_INSTALL_RECEIPT_SCHEMA
            or install_receipt.get("status") != "succeeded"
            or install_receipt.get("claimSha256")
            != _sha256_file(paths["installClaim"])
            or install_claim.get("authorizationId")
            != expected_authorization
            or install_receipt.get("authorizationId")
            != expected_authorization
            or install_claim.get("recipient") != FINAL_RUNNER_RECIPIENT
            or install_receipt.get("recipient") != FINAL_RUNNER_RECIPIENT
            or install_claim.get("bundleIdentifier")
            != FINAL_RUNNER_BUNDLE_ID
            or install_receipt.get("bundleIdentifier")
            != FINAL_RUNNER_BUNDLE_ID
            or install_claim.get("buildReceiptSha256") != build_receipt_sha
            or install_receipt.get("buildReceiptSha256") != build_receipt_sha
            or install_claim.get("buildClaimSha256")
            != _sha256_file(paths["buildClaim"])
            or install_claim.get("evidence") != evidence
            or install_claim.get("productEntitySha256")
            != product["entitySha256"]
            or install_claim.get("productApplicationSha256")
            != product["applicationSha256"]
        ):
            raise IncompleteEvidence(
                "manual_trace_final_runner_install_receipt_binding_invalid"
            )
        if self.authorized_retry_requested:
            if (
                build_claim.get("attemptNamespace")
                != FINAL_RUNNER_AUTHORIZED_RETRY_ATTEMPT
                or build_receipt.get("attemptNamespace")
                != FINAL_RUNNER_AUTHORIZED_RETRY_ATTEMPT
                or install_claim.get("attemptNamespace")
                != FINAL_RUNNER_AUTHORIZED_RETRY_ATTEMPT
                or install_receipt.get("attemptNamespace")
                != FINAL_RUNNER_AUTHORIZED_RETRY_ATTEMPT
                or build_claim.get("namespaceRelativePath")
                != (
                    FINAL_RUNNER_ARTIFACT_RELATIVE
                    / FINAL_RUNNER_AUTHORIZED_RETRY_NAMESPACE_NAME
                ).as_posix()
                or build_claim.get("retryAuthority")
                != retry_authority_before
                or build_receipt.get("retryAuthority")
                != retry_authority_before
                or install_claim.get("retryAuthority")
                != retry_authority_before
                or install_receipt.get("retryAuthority")
                != retry_authority_before
            ):
                raise IncompleteEvidence(
                    "manual_trace_retry_namespace_receipt_mixed"
                )
            retained_product = (
                namespace / FINAL_RUNNER_AUTHORIZED_RETRY_PRODUCT_NAME
            )
            if retained_product.is_symlink() or not retained_product.is_dir():
                raise IncompleteEvidence(
                    "manual_trace_retry_retained_product_invalid"
                )
            files: dict[str, str] = {}
            for entry in sorted(
                retained_product.rglob("*"),
                key=lambda value: value.relative_to(
                    retained_product
                ).as_posix(),
            ):
                if entry.is_symlink():
                    raise IncompleteEvidence(
                        "manual_trace_retry_retained_product_contains_symlink"
                    )
                if entry.is_file():
                    files[
                        entry.relative_to(retained_product).as_posix()
                    ] = _sha256_file(entry)
            expected_install_argv = [
                "xcrun",
                "devicectl",
                "device",
                "install",
                "app",
                "--device",
                FINAL_RUNNER_RECIPIENT,
                str(retained_product.resolve()),
            ]
            if (
                product.get("entitySha256")
                != _entity_digest(retained_product)
                or product.get("applicationSha256")
                != _application_digest(retained_product)
                or product.get("fileSha256") != files
                or install_claim.get("installArgv")
                != expected_install_argv
                or install_receipt.get("installArgv")
                != expected_install_argv
            ):
                raise IncompleteEvidence(
                    "manual_trace_retry_retained_product_changed"
                )
        elif any(
            key in value
            for value in (
                build_claim,
                build_receipt,
                install_claim,
                install_receipt,
            )
            for key in ("attemptNamespace", "retryAuthority")
        ):
            raise IncompleteEvidence(
                "manual_trace_final_runner_namespace_receipt_mixed"
            )
        pre_inventory = install_receipt.get("preInventory")
        post_inventory = install_receipt.get("postInventory")
        pre_samples = install_receipt.get("preContinuitySamples")
        post_sample = install_receipt.get("postContinuitySample")
        if (
            not isinstance(pre_inventory, dict)
            or not isinstance(post_inventory, dict)
            or not isinstance(pre_samples, list)
            or len(pre_samples) != 2
            or install_claim.get("preInventory") != pre_inventory
            or install_claim.get("preContinuitySamples") != pre_samples
            or post_inventory.get("bundleIdentifier")
            != FINAL_RUNNER_BUNDLE_ID
            or post_inventory.get("executableName") != "Runner"
            or post_inventory.get("bundleShortVersion")
            != product["bundleShortVersion"]
            or post_inventory.get("bundleVersion")
            != product["bundleVersion"]
        ):
            raise IncompleteEvidence(
                "manual_trace_final_runner_continuity_invalid"
            )
        try:
            first_pre_fields = _continuity_stable_fields(
                pre_samples[0],
                "manual_trace_final_runner_continuity_invalid",
            )
            second_pre_fields = _continuity_stable_fields(
                pre_samples[1],
                "manual_trace_final_runner_continuity_invalid",
            )
            post_fields = _continuity_stable_fields(
                post_sample,
                "manual_trace_final_runner_continuity_invalid",
            )
        except (KeyError, TypeError) as error:
            raise IncompleteEvidence(
                "manual_trace_final_runner_continuity_invalid"
            ) from error
        if (
            first_pre_fields != second_pre_fields
            or pre_samples[0]["inventory"] != pre_samples[1]["inventory"]
            or second_pre_fields != post_fields
            or pre_samples[1]["inventory"] != pre_inventory
            or post_sample["inventory"] != post_inventory
            or pre_inventory.get("url") == post_inventory.get("url")
        ):
            raise IncompleteEvidence(
                "manual_trace_final_runner_continuity_invalid"
            )
        if self.authorized_retry_requested and (
            _validate_authorized_retry_authority(authority_artifact)
            != retry_authority_before
        ):
            raise IncompleteEvidence(
                "manual_trace_retry_authority_changed_during_binding"
            )
        return {
            "authorizationId": expected_authorization,
            "productReceiptSha256": build_receipt_sha,
            "installTerminalSha256": install_receipt_sha,
            "attempt02ReceiptSha256": attempt_02_sha,
        }

    def _validate_manual_attempt_absent(self) -> None:
        if _path_present(self.trace_artifact) or _path_present(self.trace_claim):
            raise IncompleteEvidence("manual_trace_artifact_or_claim_already_exists")
        if _path_present(self.trace_terminal_receipt):
            raise IncompleteEvidence(
                "manual_trace_final_attempt_terminal_receipt_already_exists"
            )
        if _path_present(
            self.artifact_directory / f"{SCENARIO}_orchestrator_verdict.json"
        ):
            raise IncompleteEvidence(
                "manual_trace_orchestrator_verdict_already_exists"
            )
        if _path_present(self.paths.lease):
            raise IncompleteEvidence("manual_trace_active_lease_already_exists")

    def _validate_live_artifact_directory_path(self) -> None:
        path = self.artifact_directory_argument
        if self.authorized_retry_requested:
            expected = (
                self.project_root
                / FINAL_RUNNER_AUTHORIZED_RETRY_LIVE_ARTIFACT_RELATIVE
            ).resolve()
            if self.artifact_directory != expected:
                raise IncompleteEvidence(
                    "live_diagnostic_retry_artifact_directory_invalid"
                )
        if not _path_present(path):
            return
        if path.is_symlink() or not path.is_dir():
            raise IncompleteEvidence("live_diagnostic_artifact_directory_invalid")

    def _validate_live_artifact_directory_fresh(self) -> None:
        self._validate_live_artifact_directory_path()
        if not _path_present(self.artifact_directory_argument):
            return
        try:
            if next(self.artifact_directory_argument.iterdir(), None) is not None:
                raise IncompleteEvidence(
                    "live_diagnostic_artifact_directory_not_fresh"
                )
        except OSError as error:
            raise IncompleteEvidence(
                "live_diagnostic_artifact_directory_unreadable"
            ) from error

    def _validate_manual_inputs(self) -> None:
        if not self.project_root.is_dir():
            raise IncompleteEvidence("manual_trace_project_root_missing")
        if self.args.run_id != "existing-state-manual-trace":
            raise IncompleteEvidence("manual_trace_owner_invalid")
        if not self.args.single_owner:
            raise IncompleteEvidence("manual_trace_single_owner_required")
        if not SAFE_ID_RE.fullmatch(self.args.sender) or not SAFE_ID_RE.fullmatch(
            self.args.recipient
        ):
            raise IncompleteEvidence("manual_trace_unsafe_device_id")
        if not SAFE_TARGET_RE.fullmatch(self.relay_target):
            raise IncompleteEvidence("manual_trace_unsafe_relay_target")
        if not SAFE_ID_RE.fullmatch(self.group_name) or not SAFE_ID_RE.fullmatch(
            self.existing_target_marker
        ):
            raise IncompleteEvidence("manual_trace_group_or_target_invalid")
        if not self.relay_addresses:
            raise IncompleteEvidence("manual_trace_relay_addresses_required")
        for required, code in (
            (self.prior_authority_path, "manual_trace_prior_authority_missing"),
            (self.staging_manifest, "manual_trace_staging_manifest_missing"),
            (self.relay_key, "manual_trace_relay_key_missing"),
            (self.paths.receipt, "manual_trace_deployment_receipt_missing"),
            (self.paths.prior_relay, "manual_trace_prior_relay_missing"),
            (self.paths.candidate_relay, "manual_trace_candidate_relay_missing"),
            (self.paths.prior_manifest, "manual_trace_prior_manifest_missing"),
            (
                self.paths.candidate_manifest,
                "manual_trace_candidate_manifest_missing",
            ),
        ):
            if not required.is_file() or required.is_symlink():
                raise IncompleteEvidence(code)
        if self.live_diagnostic:
            self._validate_live_artifact_directory_path()
        else:
            if not self.trace_failure.is_file() or self.trace_failure.is_symlink():
                raise IncompleteEvidence("manual_trace_retained_failure_missing")
            _require_private(
                self.trace_failure,
                "manual_trace_retained_failure_not_private",
            )
            if _sha256_file(self.trace_failure) != self.expected_failure_sha256:
                raise IncompleteEvidence("manual_trace_retained_failure_changed")
        if not self.live_diagnostic:
            self._validate_manual_attempt_absent()
        legacy_final_values = [
            self.final_attempt_authorization_id,
            *self.final_attempt_hashes.values(),
        ]
        receipt_values = [
            self.final_runner_product_receipt_sha256,
            self.final_runner_install_terminal_sha256,
            self.final_attempt_02_receipt_sha256,
        ]
        final_values = [*legacy_final_values, *receipt_values]
        final_requested = any(value is not None for value in final_values)
        prior_archive_requested = any(
            value is not None
            for value in self.prior_manual_preclaim_hashes.values()
        )
        if self.authorized_retry_requested and not self.live_diagnostic:
            raise IncompleteEvidence(
                "manual_trace_retry_requires_live_diagnostic"
            )
        if self.live_diagnostic and not self.authorized_retry_requested and (
            self.args.retained_failure_sha256 is not None
            or final_requested
            or prior_archive_requested
        ):
            raise IncompleteEvidence(
                "live_diagnostic_legacy_authority_arguments_forbidden"
            )
        if self.authorized_retry_requested:
            if (
                self.attempt_namespace
                != FINAL_RUNNER_AUTHORIZED_RETRY_ATTEMPT
                or self.args.retained_failure_sha256 is not None
                or prior_archive_requested
                or any(value is not None for value in legacy_final_values)
                or not all(value is not None for value in receipt_values)
                or self.args.sender != FINAL_ATTEMPT_PIXEL_ID
                or self.args.recipient != FINAL_RUNNER_RECIPIENT
            ):
                raise IncompleteEvidence(
                    "live_diagnostic_retry_authority_invalid"
                )
            self.final_runner_product_receipt_sha256 = _require_sha(
                self.final_runner_product_receipt_sha256,
                "live_diagnostic_retry_product_receipt_sha_invalid",
            )
            self.final_runner_install_terminal_sha256 = _require_sha(
                self.final_runner_install_terminal_sha256,
                "live_diagnostic_retry_install_terminal_sha_invalid",
            )
            self.final_attempt_02_receipt_sha256 = _require_sha(
                self.final_attempt_02_receipt_sha256,
                "live_diagnostic_retry_attempt_02_receipt_sha_invalid",
            )
            return
        if final_requested and not all(value is not None for value in final_values):
            raise IncompleteEvidence("manual_trace_final_attempt_authority_incomplete")
        if final_requested:
            if self.final_attempt_authorization_id != FINAL_ATTEMPT_AUTHORIZATION:
                raise IncompleteEvidence(
                    "manual_trace_final_attempt_authorization_invalid"
                )
            if self.args.sender != FINAL_ATTEMPT_PIXEL_ID:
                raise IncompleteEvidence("manual_trace_final_attempt_pixel_invalid")
            if self.args.recipient != FINAL_RUNNER_RECIPIENT:
                raise IncompleteEvidence(
                    "manual_trace_final_attempt_recipient_invalid"
                )
            for key, value in self.final_attempt_hashes.items():
                self.final_attempt_hashes[key] = _require_sha(
                    value,
                    f"manual_trace_final_attempt_{key}_sha_invalid",
                )
                if self.final_attempt_hashes[key] != FINAL_ATTEMPT_02_HASHES[key]:
                    raise IncompleteEvidence(
                        f"manual_trace_final_attempt_{key}_not_reviewed"
                    )
            self.final_runner_product_receipt_sha256 = _require_sha(
                self.final_runner_product_receipt_sha256,
                "manual_trace_final_runner_product_receipt_sha_invalid",
            )
            self.final_runner_install_terminal_sha256 = _require_sha(
                self.final_runner_install_terminal_sha256,
                "manual_trace_final_runner_install_terminal_sha_invalid",
            )
            self.final_attempt_02_receipt_sha256 = _require_sha(
                self.final_attempt_02_receipt_sha256,
                "manual_trace_final_attempt_02_receipt_sha_invalid",
            )

    def _retained_deployment_receipt(
        self, authority: Mapping[str, Any]
    ) -> dict[str, Any]:
        receipt = _read_json(
            self.paths.receipt,
            "manual_trace_deployment_receipt_invalid",
        )
        _require_private(
            self.paths.receipt,
            "manual_trace_deployment_receipt_not_private",
        )
        if (
            receipt.get("schema") != RECEIPT_SCHEMA
            or receipt.get("ownerRunId") != CAMPAIGN_OWNER
            or receipt.get("singleOwnerDeclared") is not True
        ):
            raise IncompleteEvidence("manual_trace_deployment_receipt_shape_invalid")
        for key in (
            "candidateRelaySha256",
            "priorRelaySha256",
            "priorManifestSha256",
            "candidateManifestSha256",
        ):
            _require_sha(
                receipt.get(key),
                f"manual_trace_deployment_receipt_{key}_invalid",
            )
        if (
            receipt["priorRelaySha256"] != authority["priorRelaySha256"]
            or receipt["priorManifestSha256"] != authority["priorManifestSha256"]
            or _sha256_file(self.paths.prior_relay)
            != receipt["priorRelaySha256"]
            or _sha256_file(self.paths.candidate_relay)
            != receipt["candidateRelaySha256"]
            or _sha256_file(self.paths.prior_manifest)
            != receipt["priorManifestSha256"]
            or _sha256_file(self.paths.candidate_manifest)
            != receipt["candidateManifestSha256"]
            or _sha256_file(self.staging_manifest)
            != receipt["priorManifestSha256"]
        ):
            raise IncompleteEvidence("manual_trace_retained_deployment_binding_changed")
        revision = receipt.get("candidateRelayRevision")
        if not isinstance(revision, str) or not revision:
            raise IncompleteEvidence("manual_trace_candidate_revision_invalid")
        return receipt

    def _prepare_trace_manifest(
        self, receipt: Mapping[str, Any]
    ) -> None:
        candidate = _read_json(
            self.paths.candidate_manifest,
            "manual_trace_candidate_manifest_invalid",
        )
        ios_capture = candidate.get("iosCapture")
        addresses = candidate.get("relayAddresses")
        if (
            candidate.get("environment") != "staging"
            or candidate.get("relayActive") is not True
            or candidate.get("providerConfigured") is not True
            or candidate.get("providerProbeSucceeded") is not True
            or candidate.get("productionDeploymentPerformed") is not False
            or candidate.get("provider") != "apns"
            or candidate.get("candidateRelayRevision")
            != receipt["candidateRelayRevision"]
            or candidate.get("candidateRelaySha256")
            != receipt["candidateRelaySha256"]
            or addresses != self.relay_addresses
            or not isinstance(ios_capture, dict)
            or ios_capture.get("bundleId") != "com.mknoon.app"
            or ios_capture.get("systemLogExecutable") != "idevicesyslog"
        ):
            raise IncompleteEvidence("manual_trace_candidate_manifest_contract_invalid")
        trace = {
            "schema": TRACE_MANIFEST_SCHEMA,
            "version": 1,
            "environment": "staging",
            "relayActive": True,
            "providerConfigured": True,
            "providerProbeSucceeded": True,
            "productionDeploymentPerformed": False,
            "allowAppDataReset": False,
            "candidateRelayRevision": receipt["candidateRelayRevision"],
            "candidateRelaySha256": receipt["candidateRelaySha256"],
            "provider": "apns",
            "relayAddresses": addresses,
            "iosCapture": {
                "bundleId": "com.mknoon.app",
                "systemLogExecutable": "idevicesyslog",
            },
        }
        self.artifact_directory.mkdir(parents=True, exist_ok=True)
        _retain_equal(self.trace_manifest, _canonical_json(trace), private=True)

    def _write_trace_relay_state(
        self,
        *,
        status: str,
        receipt: Mapping[str, Any],
    ) -> None:
        _write_json_atomic(
            self.trace_relay_state,
            {
                "schema": TRACE_RELAY_STATE_SCHEMA,
                "status": status,
                "ownerRunId": self.args.run_id,
                **(
                    {"authorityMode": "live_diagnostic"}
                    if self.live_diagnostic
                    else {"retainedFailureSha256": self.expected_failure_sha256}
                ),
                "candidateRelaySha256": receipt["candidateRelaySha256"],
                "priorRelaySha256": receipt["priorRelaySha256"],
                "priorManifestSha256": receipt["priorManifestSha256"],
                "traceManifestSha256": _sha256_file(self.trace_manifest),
            },
            private=True,
        )

    def _deploy_relay_only(self, receipt: Mapping[str, Any], nonce: str) -> None:
        identity = self._remote_identity()
        if (
            identity["installedSha256"] != receipt["priorRelaySha256"]
            or identity["runningSha256"] != receipt["priorRelaySha256"]
        ):
            raise IncompleteEvidence("manual_trace_prior_relay_not_live")
        self.deployed = True
        self._install_remote_binary(
            self.paths.candidate_relay,
            nonce,
            "manual_trace_candidate",
        )
        identity = self._remote_identity()
        if (
            identity["installedSha256"] != receipt["candidateRelaySha256"]
            or identity["runningSha256"] != receipt["candidateRelaySha256"]
            or receipt["candidateRelayRevision"] not in identity["version"]
        ):
            raise IncompleteEvidence("manual_trace_candidate_identity_mismatch")
        self._write_trace_relay_state(status="candidate_active", receipt=receipt)

    def _restore_relay_only(
        self,
        receipt: Mapping[str, Any],
        nonce: str,
        *,
        retain_state: bool = True,
    ) -> None:
        identity = self._remote_identity()
        prior_sha = receipt["priorRelaySha256"]
        candidate_sha = receipt["candidateRelaySha256"]
        if not (
            identity["installedSha256"] == prior_sha
            and identity["runningSha256"] == prior_sha
        ):
            if (
                identity["installedSha256"] not in {prior_sha, candidate_sha}
                or identity["runningSha256"] not in {prior_sha, candidate_sha}
            ):
                raise IncompleteEvidence("manual_trace_restore_identity_unjoinable")
            self._install_remote_binary(
                self.paths.prior_relay,
                nonce,
                "manual_trace_restore",
            )
        final_identity = self._remote_identity()
        if (
            final_identity["installedSha256"] != prior_sha
            or final_identity["runningSha256"] != prior_sha
            or _sha256_file(self.staging_manifest) != receipt["priorManifestSha256"]
            or (
                not self.live_diagnostic
                and _sha256_file(self.trace_failure)
                != self.expected_failure_sha256
            )
        ):
            raise IncompleteEvidence("manual_trace_verified_restoration_failed")
        if retain_state:
            self._write_trace_relay_state(status="restored", receipt=receipt)
        self.restored = True

    def _restore_stranded_live_relay(self, receipt: Mapping[str, Any], nonce: str) -> None:
        if not self.live_diagnostic:
            return
        identity = self._remote_identity()
        prior_sha = receipt["priorRelaySha256"]
        candidate_sha = receipt["candidateRelaySha256"]
        if (
            identity["installedSha256"] == prior_sha
            and identity["runningSha256"] == prior_sha
        ):
            return
        if (
            identity["installedSha256"] not in {prior_sha, candidate_sha}
            or identity["runningSha256"] not in {prior_sha, candidate_sha}
        ):
            raise IncompleteEvidence("live_diagnostic_relay_identity_unjoinable")
        self.deployed = True
        self._restore_relay_only(receipt, nonce, retain_state=False)
        raise IncompleteEvidence("live_diagnostic_stranded_candidate_restored")

    def _validate_live_diagnostic_outputs(self) -> None:
        for path, code in (
            (self.trace_claim, "live_diagnostic_claim_invalid"),
            (self.trace_artifact, "live_diagnostic_artifact_invalid"),
            (
                self.trace_terminal_receipt,
                "live_diagnostic_terminal_receipt_invalid",
            ),
        ):
            _require_private_regular(path, code)

        claim = _read_json(self.trace_claim, "live_diagnostic_claim_invalid")
        artifact = _read_json(
            self.trace_artifact, "live_diagnostic_artifact_invalid"
        )
        terminal = _read_json(
            self.trace_terminal_receipt,
            "live_diagnostic_terminal_receipt_invalid",
        )
        claim_value = claim.get("claimValue")
        if (
            claim.get("schema") != TRACE_CLAIM_SCHEMA
            or claim.get("ownerRunId") != "existing-state-trace"
            or claim.get("singleOwnerDeclared") is not True
            or not isinstance(claim_value, str)
            or not claim_value
            or len(claim_value) > 200
        ):
            raise IncompleteEvidence("live_diagnostic_claim_invalid")
        if (
            artifact.get("schema") != TRACE_LIVE_ARTIFACT_SCHEMA
            or artifact.get("version") != 1
            or artifact.get("authorityMode") != TRACE_LIVE_AUTHORITY_MODE
            or artifact.get("status") != "trace_complete"
            or artifact.get("closurePassed") is not False
            or artifact.get("traceAttemptClaimed") is not True
            or artifact.get("traceAttemptClaimSha256")
            != _sha256_file(self.trace_claim)
            or artifact.get("disposition") not in TRACE_LIVE_DISPOSITIONS
        ):
            raise IncompleteEvidence("live_diagnostic_artifact_invalid")
        if (
            terminal.get("schema") != TRACE_LIVE_TERMINAL_RECEIPT_SCHEMA
            or terminal.get("version") != 1
            or terminal.get("scenario") != SCENARIO
            or terminal.get("authorityMode") != TRACE_LIVE_AUTHORITY_MODE
            or terminal.get("terminalStatus") != "success"
            or terminal.get("captureExitCode") != 0
            or terminal.get("traceAttemptClaimed") is not True
        ):
            raise IncompleteEvidence("live_diagnostic_terminal_receipt_invalid")
        legacy_keys = {
            "attempt",
            "authorization",
            "finalRunnerProductReceiptSha256",
            "finalRunnerInstallTerminalSha256",
            "attempt02ReceiptSha256",
        }
        if legacy_keys.intersection(artifact) or legacy_keys.intersection(terminal):
            raise IncompleteEvidence("live_diagnostic_legacy_authority_leaked")

    def _revalidate_runner_binding_after_restoration(self) -> None:
        if not self._runner_binding_requested():
            return
        if not self.restored or self.final_runner_binding is None:
            raise IncompleteEvidence(
                "manual_trace_runner_binding_post_restore_missing"
            )
        revalidated = self._validate_selected_runner_binding()
        if revalidated != self.final_runner_binding:
            raise IncompleteEvidence(
                "manual_trace_runner_binding_changed_during_pause"
            )
        self.final_runner_binding = revalidated

    def _seal_authorized_retry_live_receipt(self) -> None:
        if not self.authorized_retry_requested:
            return
        if self.final_runner_binding is None or not self.restored:
            raise IncompleteEvidence(
                "live_diagnostic_retry_terminal_binding_missing"
            )
        if _path_present(self.trace_failure):
            raise IncompleteEvidence(
                "live_diagnostic_retry_failure_artifact_present"
            )
        for path, code in (
            (self.trace_claim, "live_diagnostic_retry_claim_invalid"),
            (self.trace_artifact, "live_diagnostic_retry_artifact_invalid"),
            (
                self.trace_terminal_receipt,
                "live_diagnostic_retry_inner_terminal_invalid",
            ),
            (self.trace_manifest, "live_diagnostic_retry_manifest_invalid"),
            (
                self.trace_relay_state,
                "live_diagnostic_retry_relay_state_invalid",
            ),
        ):
            _require_private_regular(path, code)
        payload = {
            "schema": TRACE_AUTHORIZED_RETRY_RECEIPT_SCHEMA,
            "version": 1,
            "status": "success",
            "attemptNamespace": FINAL_RUNNER_AUTHORIZED_RETRY_ATTEMPT,
            "authorizationId": FINAL_RUNNER_AUTHORIZED_RETRY_AUTHORIZATION,
            "outputRelativePath": (
                FINAL_RUNNER_AUTHORIZED_RETRY_LIVE_ARTIFACT_RELATIVE.as_posix()
            ),
            "relayRestored": True,
            "productReceiptSha256": self.final_runner_binding[
                "productReceiptSha256"
            ],
            "installTerminalSha256": self.final_runner_binding[
                "installTerminalSha256"
            ],
            "attempt02ReceiptSha256": self.final_runner_binding[
                "attempt02ReceiptSha256"
            ],
            "traceClaimSha256": _sha256_file(self.trace_claim),
            "traceArtifactSha256": _sha256_file(self.trace_artifact),
            "traceTerminalReceiptSha256": _sha256_file(
                self.trace_terminal_receipt
            ),
            "traceManifestSha256": _sha256_file(self.trace_manifest),
            "traceRelayStateSha256": _sha256_file(self.trace_relay_state),
            "failureArtifactAbsent": True,
        }
        _write_no_replace(
            self.authorized_retry_terminal_receipt,
            _canonical_json(payload),
            private=True,
            code="live_diagnostic_retry_terminal_receipt_collision",
        )
        _require_private_regular(
            self.authorized_retry_terminal_receipt,
            "live_diagnostic_retry_terminal_receipt_invalid",
        )
        if (
            self.authorized_retry_terminal_receipt.read_bytes()
            != _canonical_json(payload)
            or self._validate_selected_runner_binding()
            != self.final_runner_binding
        ):
            raise IncompleteEvidence(
                "live_diagnostic_retry_terminal_receipt_binding_changed"
            )

    def _finalize_manual_runner_after_restoration(
        self, runner_status: int
    ) -> None:
        """Accept child output only after restoration and authority recheck."""

        if runner_status != 0:
            raise IncompleteEvidence(
                f"manual_trace_runner_failed_{runner_status}"
            )
        self._revalidate_runner_binding_after_restoration()
        if self.live_diagnostic:
            self._validate_live_diagnostic_outputs()
            self._seal_authorized_retry_live_receipt()
        else:
            if not self.trace_artifact.is_file() or not self.trace_claim.is_file():
                raise IncompleteEvidence(
                    "manual_trace_artifact_or_claim_missing"
                )
            _require_private(self.trace_claim, "manual_trace_claim_not_private")
            if _sha256_file(self.trace_failure) != self.expected_failure_sha256:
                raise IncompleteEvidence("manual_trace_retained_failure_changed")

    def _manual_runner_command(self) -> list[str]:
        dart = _command_from_environment("PLAN398_DART_COMMAND", ["dart"])
        command = [
            *dart,
            "run",
            "integration_test/scripts/run_group_reaction_notification_device.dart",
            "--scenario",
            SCENARIO,
            "--trace-only-existing-state",
            "--manual-send-existing-state",
            "--no-child-builds",
            "--sender",
            self.args.sender,
            "--recipient",
            self.args.recipient,
            "--artifact-dir",
            str(self.artifact_directory),
            "--staging-manifest",
            str(self.trace_manifest),
            "--relay-target",
            self.relay_target,
            "--relay-key",
            str(self.relay_key),
            "--group-name",
            self.group_name,
            "--existing-target-marker",
            self.existing_target_marker,
            *(["--live-diagnostic"] if self.live_diagnostic else []),
        ]
        # The legacy non-live final attempt forwards these receipts to its
        # downstream authority mode.  Live diagnostic rejects those legacy
        # flags; authorized-retry-01 is instead fully bound and revalidated by
        # this Python owner immediately before the ordinary live invocation.
        if self._final_attempt_requested():
            if self.final_runner_binding is None:
                raise IncompleteEvidence(
                    "manual_trace_final_runner_binding_missing"
                )
            command.extend(
                [
                    "--plan398-final-attempt-authorization-id",
                    self.final_runner_binding["authorizationId"],
                    "--plan398-final-runner-product-receipt-sha256",
                    self.final_runner_binding["productReceiptSha256"],
                    "--plan398-final-runner-install-terminal-sha256",
                    self.final_runner_binding["installTerminalSha256"],
                    "--plan398-attempt-02-receipt-sha256",
                    self.final_runner_binding["attempt02ReceiptSha256"],
                ]
            )
        return command

    def _start_manual_runner(self) -> int:
        if self._runner_binding_requested():
            revalidated = self._validate_selected_runner_binding()
            if revalidated != self.final_runner_binding:
                raise IncompleteEvidence(
                    "manual_trace_final_runner_binding_changed_before_invocation"
                )
            self.final_runner_binding = revalidated
        _event("manual_trace_runner_start")
        try:
            self.child = subprocess.Popen(
                self._manual_runner_command(),
                cwd=self.project_root,
                env=os.environ.copy(),
                text=True,
                start_new_session=True,
            )
        except OSError as error:
            raise IncompleteEvidence("manual_trace_runner_launch_failed") from error
        return self.child.wait()

    def _stop_manual_runner(self) -> None:
        child = self.child
        if child is None or child.poll() is not None:
            return
        try:
            os.killpg(child.pid, signal.SIGTERM)
        except ProcessLookupError:
            return
        try:
            child.wait(timeout=10)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            child.wait(timeout=10)

    def run(self) -> int:
        self._validate_manual_inputs()
        prelock_final_binding: dict[str, str] | None = None
        if self._runner_binding_requested():
            prelock_final_binding = self._validate_selected_runner_binding()
        lock = self.acquire_lock()
        receipt: dict[str, Any] | None = None
        nonce = os.urandom(16).hex()
        runner_status: int | None = None
        primary_error: BaseException | None = None
        restoration_error: BaseException | None = None
        try:
            if not self.live_diagnostic:
                self._validate_manual_attempt_absent()
            authority = self._prior_authority()
            receipt = self._retained_deployment_receipt(authority)
            self._restore_stranded_live_relay(receipt, nonce)
            if self.live_diagnostic:
                self._validate_live_artifact_directory_fresh()
            if self._runner_binding_requested():
                if not self.authorized_retry_requested:
                    _validate_fixed_final_attempt_evidence(
                        self.artifact_directory
                    )
            elif not self.live_diagnostic:
                self._archive_prior_manual_preclaim_evidence()
            self._prepare_trace_manifest(receipt)
            if self._runner_binding_requested():
                locked_final_binding = self._validate_selected_runner_binding()
                if (
                    prelock_final_binding is None
                    or locked_final_binding != prelock_final_binding
                ):
                    raise IncompleteEvidence(
                        "manual_trace_final_runner_binding_changed_while_waiting_for_lock"
                    )
                self.final_runner_binding = locked_final_binding
            self._validate_manual_attempt_absent()
            self._deploy_relay_only(receipt, nonce)
            try:
                runner_status = self._start_manual_runner()
                if self._signal is not None:
                    raise InterruptedTransaction(self._signal)
            except BaseException as error:
                primary_error = error
            finally:
                self._stop_manual_runner()
            try:
                self._restore_relay_only(receipt, nonce)
            except BaseException as error:
                restoration_error = error

            if restoration_error is not None:
                raise restoration_error
            if primary_error is not None:
                raise primary_error
            self._finalize_manual_runner_after_restoration(runner_status)
            print("TRACE_COMPLETE: manual Plan 398 send sealed and relay restored.")
            return 0
        finally:
            try:
                if self.deployed and not self.restored and receipt is not None:
                    self._stop_manual_runner()
                    self._restore_relay_only(receipt, os.urandom(16).hex())
            finally:
                lock.close()


class CurrentSourceRestart:
    """Archive one restored pre-claim campaign under literal authorization."""

    def __init__(self, args: argparse.Namespace) -> None:
        self.project_root = Path(args.project_root).resolve()
        self.paths = Paths(self.project_root)
        self.authorization_id = args.authorization_id
        self.retained_digest = _require_sha(
            args.retained_source_digest,
            "restart_retained_source_digest_invalid",
        )
        self.current_digest = _require_sha(
            args.current_source_digest,
            "restart_current_source_digest_invalid",
        )
        archive_name = (
            "current-source-restart-"
            f"{self.retained_digest[:12]}-{self.current_digest[:12]}"
        )
        self.archive = self.paths.preclaim_campaign_archives / archive_name
        self.archive_receipt = (
            self.paths.preclaim_campaign_archives / f"{archive_name}.json"
        )

    def _validate_arguments(self) -> None:
        if not self.project_root.is_dir():
            raise IncompleteEvidence("restart_project_root_missing")
        if self.authorization_id != CURRENT_SOURCE_RESTART_AUTHORIZATION:
            raise IncompleteEvidence("restart_authorization_invalid")
        if self.retained_digest == self.current_digest:
            raise IncompleteEvidence("restart_source_digest_unchanged")
        test_interrupt = os.environ.get(
            "PLAN398_TEST_RESTART_INTERRUPT_AFTER_MOVE", ""
        )
        if test_interrupt not in ("", "1"):
            raise IncompleteEvidence("restart_test_interrupt_value_invalid")
        if test_interrupt and os.environ.get("PLAN398_TEST_MODE") != "1":
            raise IncompleteEvidence("restart_test_interrupt_forbidden")

    @staticmethod
    def _private_json(path: Path, code: str) -> dict[str, Any]:
        if path.is_symlink() or not path.is_file():
            raise IncompleteEvidence(code)
        _require_private(path, code)
        return _read_json(path, code)

    def _validate_retained_campaign(self, campaign: Path) -> dict[str, str]:
        if campaign.is_symlink() or not campaign.is_dir():
            raise IncompleteEvidence("restart_retained_campaign_invalid")

        active_lease = campaign / "active-transaction-lease.json"
        authoritative_artifact = (
            campaign
            / "physical-proof"
            / "diagnostic-message-window"
            / f"{SCENARIO}.json"
        )
        if _path_present(active_lease):
            raise IncompleteEvidence("restart_active_lease_present")
        if _path_present(authoritative_artifact):
            raise IncompleteEvidence("restart_authoritative_artifact_present")

        receipt_path = campaign / "deployment-state.json"
        snapshot_path = campaign / "prepared-snapshot.json"
        restoration_path = campaign / "restoration-state.json"
        receipt = self._private_json(
            receipt_path, "restart_deployment_receipt_invalid"
        )
        snapshot = self._private_json(
            snapshot_path, "restart_prepared_snapshot_invalid"
        )
        restoration = self._private_json(
            restoration_path, "restart_restoration_receipt_invalid"
        )

        expected_snapshot_keys = {
            "schema",
            "ownerRunId",
            "suiteSourceDigest",
            "android",
            "ios",
            "iosSetup",
            "relayCandidateSha256",
            "relayRevision",
        }
        expected_receipt_keys = {
            "schema",
            "ownerRunId",
            "singleOwnerDeclared",
            "priorAuthoritySha256",
            "relayTargetSha256",
            "stagingManifestPathSha256",
            "suiteSourceDigest",
            "preparedSnapshotSha256",
            "android",
            "ios",
            "iosSetup",
            "candidateRelaySha256",
            "candidateRelayRevision",
            "priorRelaySha256",
            "priorRelayVersion",
            "priorManifestSha256",
            "candidateManifestSha256",
        }
        expected_restoration_keys = {
            "schema",
            "status",
            "ownerRunId",
            "priorRelaySha256",
            "priorManifestSha256",
        }
        if (
            set(snapshot) != expected_snapshot_keys
            or snapshot.get("schema") != SNAPSHOT_SCHEMA
            or snapshot.get("ownerRunId") != CAMPAIGN_OWNER
            or snapshot.get("suiteSourceDigest") != self.retained_digest
        ):
            raise IncompleteEvidence("restart_prepared_snapshot_binding_invalid")
        if (
            set(receipt) != expected_receipt_keys
            or receipt.get("schema") != RECEIPT_SCHEMA
            or receipt.get("ownerRunId") != CAMPAIGN_OWNER
            or receipt.get("singleOwnerDeclared") is not True
            or receipt.get("suiteSourceDigest") != self.retained_digest
            or receipt.get("preparedSnapshotSha256")
            != _sha256_file(snapshot_path)
            or receipt.get("android") != snapshot.get("android")
            or receipt.get("ios") != snapshot.get("ios")
            or receipt.get("iosSetup") != snapshot.get("iosSetup")
            or receipt.get("candidateRelaySha256")
            != snapshot.get("relayCandidateSha256")
            or receipt.get("candidateRelayRevision")
            != snapshot.get("relayRevision")
        ):
            raise IncompleteEvidence("restart_deployment_snapshot_binding_invalid")

        for key in (
            "priorAuthoritySha256",
            "relayTargetSha256",
            "stagingManifestPathSha256",
            "preparedSnapshotSha256",
            "candidateRelaySha256",
            "priorRelaySha256",
            "priorManifestSha256",
            "candidateManifestSha256",
        ):
            _require_sha(receipt.get(key), f"restart_receipt_{key}_invalid")
        _require_sha(
            snapshot.get("relayCandidateSha256"),
            "restart_snapshot_candidate_relay_sha_invalid",
        )
        if not isinstance(snapshot.get("relayRevision"), str) or not snapshot[
            "relayRevision"
        ]:
            raise IncompleteEvidence("restart_snapshot_relay_revision_invalid")

        if (
            set(restoration) != expected_restoration_keys
            or restoration.get("schema") != RESTORATION_SCHEMA
            or restoration.get("status") != "restored"
            or restoration.get("ownerRunId") != CAMPAIGN_OWNER
            or restoration.get("priorRelaySha256")
            != receipt.get("priorRelaySha256")
            or restoration.get("priorManifestSha256")
            != receipt.get("priorManifestSha256")
        ):
            raise IncompleteEvidence("restart_restoration_binding_invalid")
        prior_relay_sha = _require_sha(
            restoration.get("priorRelaySha256"),
            "restart_restored_relay_sha_invalid",
        )
        prior_manifest_sha = _require_sha(
            restoration.get("priorManifestSha256"),
            "restart_restored_manifest_sha_invalid",
        )
        return {
            "restorationReceiptSha256": _sha256_file(restoration_path),
            "priorRelaySha256": prior_relay_sha,
            "priorManifestSha256": prior_manifest_sha,
        }

    def _validate_current_source(self) -> None:
        actual = _suite_source_digest(self.project_root)
        if actual != self.current_digest:
            raise IncompleteEvidence("restart_current_source_digest_mismatch")

    def _receipt_payload(
        self,
        *,
        entity_digest: str,
        restoration: Mapping[str, str],
    ) -> dict[str, Any]:
        return {
            "schema": CURRENT_SOURCE_RESTART_SCHEMA,
            "authorizationId": self.authorization_id,
            "ownerRunId": CAMPAIGN_OWNER,
            "retainedSuiteSourceDigest": self.retained_digest,
            "currentSuiteSourceDigest": self.current_digest,
            "archiveRelativePath": self.archive.relative_to(
                self.paths.campaign.parent
            ).as_posix(),
            "campaignEntitySha256": entity_digest,
            "restorationStatus": "restored",
            "restorationReceiptSha256": restoration[
                "restorationReceiptSha256"
            ],
            "priorRelaySha256": restoration["priorRelaySha256"],
            "priorManifestSha256": restoration["priorManifestSha256"],
            "diagnosticClaimAbsent": True,
            "authoritativeArtifactAbsent": True,
            "activeLeaseAbsent": True,
        }

    def _seal_receipt(self, payload: Mapping[str, Any]) -> None:
        expected = _canonical_json(payload)
        if _path_present(self.archive_receipt):
            if (
                self.archive_receipt.is_symlink()
                or not self.archive_receipt.is_file()
            ):
                raise IncompleteEvidence("restart_archive_receipt_collision")
            _require_private(
                self.archive_receipt, "restart_archive_receipt_not_private"
            )
            if self.archive_receipt.read_bytes() != expected:
                raise IncompleteEvidence("restart_archive_receipt_mismatch")
            return
        _write_json_atomic(self.archive_receipt, payload, private=True)
        _event("current_source_restart_receipt_sealed")

    def run(self) -> int:
        self._validate_arguments()
        lock = _acquire_transaction_lock(self.paths.lock)
        try:
            # The plan-wide claim deliberately remains outside the campaign
            # entity. It is therefore an explicit precondition on fresh and
            # crash-recovery paths, never something the archive can reset.
            if _path_present(self.paths.claim):
                raise IncompleteEvidence("restart_diagnostic_claim_present")

            live_present = _path_present(self.paths.campaign)
            archive_present = _path_present(self.archive)
            receipt_present = _path_present(self.archive_receipt)

            if live_present:
                if archive_present or receipt_present:
                    raise IncompleteEvidence("restart_live_archive_mixed_state")
                restoration = self._validate_retained_campaign(
                    self.paths.campaign
                )
                self._validate_current_source()
                entity_digest = _entity_digest(self.paths.campaign)

                archive_root = self.paths.preclaim_campaign_archives
                if _path_present(archive_root):
                    if archive_root.is_symlink() or not archive_root.is_dir():
                        raise IncompleteEvidence("restart_archive_root_invalid")
                else:
                    archive_root.mkdir(parents=True)
                    _fsync_directory(archive_root.parent)
                try:
                    os.replace(self.paths.campaign, self.archive)
                except OSError as error:
                    raise IncompleteEvidence("restart_campaign_move_failed") from error
                _fsync_directory(self.paths.campaign.parent)
                _fsync_directory(archive_root)
                _event("current_source_restart_campaign_moved")

                if os.environ.get(
                    "PLAN398_TEST_RESTART_INTERRUPT_AFTER_MOVE", ""
                ) == "1":
                    raise IncompleteEvidence(
                        "restart_test_interrupted_after_atomic_move"
                    )
                if _entity_digest(self.archive) != entity_digest:
                    raise IncompleteEvidence("restart_archive_entity_changed")
            else:
                if not archive_present or not self.archive.is_dir():
                    if receipt_present:
                        raise IncompleteEvidence(
                            "restart_receipt_without_exact_archive"
                        )
                    raise IncompleteEvidence("restart_live_campaign_absent")
                if self.archive.is_symlink():
                    raise IncompleteEvidence("restart_archive_invalid")
                restoration = self._validate_retained_campaign(self.archive)
                self._validate_current_source()
                entity_digest = _entity_digest(self.archive)

            payload = self._receipt_payload(
                entity_digest=entity_digest,
                restoration=restoration,
            )
            self._seal_receipt(payload)
            print(
                "RESTART_READY: restored pre-claim campaign archived for "
                "the current source tree."
            )
            return 0
        finally:
            lock.close()


def _load_claim_context() -> tuple[Transaction, dict[str, Any], dict[str, Any], dict[str, Any]]:
    required = {
        key: os.environ.get(key, "").strip()
        for key in (
            "PLAN398_PROJECT_ROOT",
            "PLAN398_ACTIVE_TRANSACTION_LEASE",
            "PLAN398_TRANSACTION_NONCE",
            "PLAN398_COORDINATOR_PID",
            "PLAN398_DEPLOYMENT_RECEIPT",
            "PLAN398_DIAGNOSTIC_ATTEMPT_MARKER",
            "PLAN398_RELAY_TARGET",
            "PLAN398_RELAY_KEY",
        )
    }
    if any(not value for value in required.values()):
        raise IncompleteEvidence("claim_send_requires_active_inherited_lease")
    project_root = Path(required["PLAN398_PROJECT_ROOT"]).resolve()
    paths = Paths(project_root)
    if Path(required["PLAN398_ACTIVE_TRANSACTION_LEASE"]).resolve() != paths.lease:
        raise IncompleteEvidence("claim_send_lease_path_mismatch")
    if Path(required["PLAN398_DEPLOYMENT_RECEIPT"]).resolve() != paths.receipt:
        raise IncompleteEvidence("claim_send_receipt_path_mismatch")
    if Path(required["PLAN398_DIAGNOSTIC_ATTEMPT_MARKER"]).resolve() != paths.claim:
        raise IncompleteEvidence("claim_send_marker_path_mismatch")

    namespace = argparse.Namespace(
        project_root=str(project_root),
        prior_authority=str(project_root / "build/plan397/deployment-state-02.json"),
        run_id=CAMPAIGN_OWNER,
        sender="claim-only",
        recipient="claim-only-recipient",
        staging_manifest=str(project_root / "unused"),
        relay_target=required["PLAN398_RELAY_TARGET"],
        relay_key=required["PLAN398_RELAY_KEY"],
        relay_addresses="unused",
        service_account=str(project_root / "unused"),
        single_owner=True,
    )
    transaction = Transaction(namespace)
    lease_path = paths.lease
    _require_private(lease_path, "claim_send_lease_not_private")
    lease = _read_json(lease_path, "claim_send_lease_invalid")
    receipt = _read_json(paths.receipt, "claim_send_receipt_invalid")
    snapshot = _read_json(paths.snapshot, "claim_send_snapshot_invalid")
    if (
        lease.get("schema") != LEASE_SCHEMA
        or lease.get("phase") != "ready_to_claim"
        or lease.get("ownerRunId") != CAMPAIGN_OWNER
        or lease.get("nonce") != required["PLAN398_TRANSACTION_NONCE"]
        or str(lease.get("coordinatorPid")) != required["PLAN398_COORDINATOR_PID"]
    ):
        raise IncompleteEvidence("claim_send_lease_binding_invalid")
    try:
        coordinator_pid = int(required["PLAN398_COORDINATOR_PID"])
        os.kill(coordinator_pid, 0)
    except (ValueError, OSError) as error:
        raise IncompleteEvidence("claim_send_coordinator_not_live") from error
    snapshot_sha = _sha256_file(paths.snapshot)
    receipt_sha = _sha256_file(paths.receipt)
    if (
        lease.get("preparedSnapshotSha256") != snapshot_sha
        or lease.get("deploymentReceiptSha256") != receipt_sha
        or receipt.get("preparedSnapshotSha256") != snapshot_sha
        or receipt.get("suiteSourceDigest") != snapshot.get("suiteSourceDigest")
    ):
        raise IncompleteEvidence("claim_send_retained_binding_invalid")
    if receipt.get("relayTargetSha256") != _sha256_text(transaction.relay_target):
        raise IncompleteEvidence("claim_send_relay_target_binding_invalid")
    receipt["sha256"] = receipt_sha
    snapshot["sha256"] = snapshot_sha
    return transaction, lease, receipt, snapshot


def claim_send() -> int:
    transaction, lease, receipt, snapshot = _load_claim_context()
    transaction._revalidate_prepared(snapshot, receipt)
    identity = transaction._remote_identity()
    if (
        identity["installedSha256"] != snapshot.get("relayCandidateSha256")
        or identity["runningSha256"] != snapshot.get("relayCandidateSha256")
        or snapshot.get("relayRevision") not in identity["version"]
    ):
        raise IncompleteEvidence("claim_send_deployed_identity_changed")
    claim = {
        "schema": CLAIM_SCHEMA,
        "ownerRunId": CAMPAIGN_OWNER,
        "claimValue": f"plan398:{os.urandom(18).hex()}",
        "deploymentReceiptSha256": receipt["sha256"],
        "preparedSnapshotSha256": snapshot["sha256"],
        "suiteSourceDigest": snapshot["suiteSourceDigest"],
        "candidateRelaySha256": snapshot["relayCandidateSha256"],
        "candidateRelayRevision": snapshot["relayRevision"],
    }
    payload = _canonical_json(claim)
    transaction.paths.claim.parent.mkdir(parents=True, exist_ok=True)
    try:
        descriptor = os.open(
            transaction.paths.claim,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL,
            0o600,
        )
    except FileExistsError as error:
        raise IncompleteEvidence("diagnostic_attempt_already_claimed") from error
    try:
        os.fchmod(descriptor, 0o600)
        os.write(descriptor, payload)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    _fsync_directory(transaction.paths.claim.parent)
    _event("claim_flushed")
    lease["phase"] = "claimed"
    _write_json_atomic(transaction.paths.lease, lease, private=True)
    print("CLAIMED: Plan 398 diagnostic send boundary.")
    return 0


class FinalRunnerUpdate:
    """One ordinary signed Release build and one same-container in-place install."""

    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.project_root = Path(args.project_root).resolve()
        self.artifact_directory = Path(args.artifact_dir).resolve()
        self.attempt_namespace = getattr(args, "attempt_namespace", None)
        self.authorized_retry = self.attempt_namespace is not None
        self.namespace_name = (
            FINAL_RUNNER_AUTHORIZED_RETRY_NAMESPACE_NAME
            if self.authorized_retry
            else FINAL_RUNNER_NAMESPACE_NAME
        )
        self.expected_authorization = (
            FINAL_RUNNER_AUTHORIZED_RETRY_AUTHORIZATION
            if self.authorized_retry
            else FINAL_ATTEMPT_AUTHORIZATION
        )
        self.namespace = self.artifact_directory / self.namespace_name
        self.build_claim = self.namespace / FINAL_RUNNER_BUILD_CLAIM_NAME
        self.build_receipt = self.namespace / FINAL_RUNNER_BUILD_RECEIPT_NAME
        self.install_claim = self.namespace / FINAL_RUNNER_INSTALL_CLAIM_NAME
        self.install_receipt = self.namespace / FINAL_RUNNER_INSTALL_RECEIPT_NAME
        self.build_product = self.project_root / "build/ios/iphoneos/Runner.app"
        self.product = (
            self.namespace / FINAL_RUNNER_AUTHORIZED_RETRY_PRODUCT_NAME
            if self.authorized_retry
            else self.build_product
        )
        self.authorization_id = args.authorization_id
        self.recipient = args.recipient
        self.bundle_id = args.bundle_id
        self.build_name = getattr(args, "build_name", None)
        self.build_number = getattr(args, "build_number", None)
        self.attempt_02_hashes = {
            "journalSha256": getattr(
                args, "final_attempt_journal_sha256", None
            ),
            "deviceLogSha256": getattr(
                args, "final_attempt_device_log_sha256", None
            ),
            "traceManifestSha256": getattr(
                args, "final_attempt_trace_manifest_sha256", None
            ),
            "traceRelayStateSha256": getattr(
                args, "final_attempt_trace_relay_state_sha256", None
            ),
        }

    @staticmethod
    def _typed_failure(error: BaseException, fallback: str) -> str:
        value = str(error)
        if re.fullmatch(r"[a-z0-9_:-]{1,240}", value):
            return value
        return fallback

    def _validate_fixed_scope(self) -> None:
        if not self.project_root.is_dir() or self.project_root.is_symlink():
            raise IncompleteEvidence("final_runner_project_root_invalid")
        expected_artifact = (
            self.project_root / FINAL_RUNNER_ARTIFACT_RELATIVE
        ).resolve()
        if self.artifact_directory != expected_artifact:
            raise IncompleteEvidence("final_runner_artifact_directory_invalid")
        if (
            self.artifact_directory.is_symlink()
            or not self.artifact_directory.is_dir()
        ):
            raise IncompleteEvidence("final_runner_artifact_directory_missing")
        if self.authorized_retry and (
            self.attempt_namespace
            != FINAL_RUNNER_AUTHORIZED_RETRY_ATTEMPT
        ):
            raise IncompleteEvidence(
                "final_runner_retry_attempt_namespace_invalid"
            )
        if self.authorization_id != self.expected_authorization:
            raise IncompleteEvidence("final_runner_authorization_invalid")
        if self.recipient != FINAL_RUNNER_RECIPIENT:
            raise IncompleteEvidence("final_runner_recipient_invalid")
        if self.bundle_id != FINAL_RUNNER_BUNDLE_ID:
            raise IncompleteEvidence("final_runner_bundle_identifier_invalid")
        expected_namespace = (
            self.project_root
            / FINAL_RUNNER_ARTIFACT_RELATIVE
            / self.namespace_name
        ).resolve()
        if self.namespace.resolve() != expected_namespace:
            raise IncompleteEvidence("final_runner_namespace_invalid")

    def _validate_build_values(self) -> None:
        if (
            not isinstance(self.build_name, str)
            or re.fullmatch(r"[0-9]+(?:\.[0-9]+){2}", self.build_name) is None
        ):
            raise IncompleteEvidence("final_runner_build_name_invalid")
        if (
            not isinstance(self.build_number, str)
            or re.fullmatch(r"[1-9][0-9]{0,17}", self.build_number) is None
        ):
            raise IncompleteEvidence("final_runner_build_number_invalid")
        for key, expected in FINAL_ATTEMPT_02_HASHES.items():
            supplied = _require_sha(
                self.attempt_02_hashes[key],
                f"final_runner_attempt_02_{key}_argument_invalid",
            )
            if supplied != expected:
                raise IncompleteEvidence(
                    f"final_runner_attempt_02_{key}_argument_changed"
                )
            self.attempt_02_hashes[key] = supplied

    def _build_argv(self, build_name: str, build_number: str) -> list[str]:
        return [
            "flutter",
            "build",
            "ios",
            "--release",
            "--target=lib/main.dart",
            "--dart-define=PRODUCTION_APNS=true",
            f"--build-name={build_name}",
            f"--build-number={build_number}",
        ]

    def _install_argv(self) -> list[str]:
        return [
            "xcrun",
            "devicectl",
            "device",
            "install",
            "app",
            "--device",
            FINAL_RUNNER_RECIPIENT,
            str(self.product.resolve()),
        ]

    def _authorized_retry_authority(self) -> dict[str, Any] | None:
        if not self.authorized_retry:
            return None
        return _validate_authorized_retry_authority(
            self.artifact_directory
        )

    def _retry_receipt_fields(
        self, authority: Mapping[str, Any] | None
    ) -> dict[str, Any]:
        if not self.authorized_retry:
            return {}
        if authority is None:
            raise IncompleteEvidence(
                "final_runner_retry_authority_missing"
            )
        return {
            "attemptNamespace": FINAL_RUNNER_AUTHORIZED_RETRY_ATTEMPT,
            "retryAuthority": dict(authority),
        }

    def _assert_trace_quiescent(self) -> None:
        for path, code in (
            (self.artifact_directory / TRACE_CLAIM_NAME, "trace_claim_present"),
            (self.artifact_directory / TRACE_ARTIFACT_NAME, "trace_artifact_present"),
            (
                self.artifact_directory
                / f"{SCENARIO}_orchestrator_verdict.json",
                "trace_verdict_present",
            ),
            (
                self.project_root
                / "build/plan398/diagnostic/active-transaction-lease.json",
                "active_transaction_lease_present",
            ),
        ):
            if _path_present(path):
                raise IncompleteEvidence(f"final_runner_{code}")

    def _ensure_namespace(self, *, expected_names: set[str]) -> None:
        if _path_present(self.namespace):
            if (
                self.namespace.is_symlink()
                or not self.namespace.is_dir()
                or stat.S_IMODE(self.namespace.stat().st_mode) != 0o700
            ):
                raise IncompleteEvidence("final_runner_namespace_not_private")
        else:
            try:
                self.namespace.mkdir(mode=0o700)
                os.chmod(self.namespace, 0o700)
                _fsync_directory(self.namespace.parent)
            except OSError as error:
                raise IncompleteEvidence(
                    "final_runner_namespace_create_failed"
                ) from error
        try:
            names = {entry.name for entry in self.namespace.iterdir()}
        except OSError as error:
            raise IncompleteEvidence("final_runner_namespace_unreadable") from error
        if names != expected_names:
            raise IncompleteEvidence("final_runner_claim_or_receipt_collision")

    def _preflight_prepare_namespace(self) -> None:
        if not _path_present(self.namespace):
            return
        if (
            self.namespace.is_symlink()
            or not self.namespace.is_dir()
            or stat.S_IMODE(self.namespace.stat().st_mode) != 0o700
        ):
            raise IncompleteEvidence("final_runner_namespace_not_private")
        try:
            if any(self.namespace.iterdir()):
                raise IncompleteEvidence(
                    "final_runner_claim_or_receipt_collision"
                )
        except OSError as error:
            raise IncompleteEvidence("final_runner_namespace_unreadable") from error

    def _seal_attempt_02(self) -> dict[str, Any]:
        """Perform the sole reviewed metadata hardening and receipt-last seal."""

        attempt_01 = _validate_fixed_final_attempt_01(self.artifact_directory)
        archive_root = self.artifact_directory / "preclaim-attempts"
        attempt_02 = archive_root / "attempt-02"
        if _path_present(attempt_02):
            raise IncompleteEvidence("final_runner_attempt_02_already_consumed")
        if (
            archive_root.is_symlink()
            or not archive_root.is_dir()
            or stat.S_IMODE(archive_root.stat().st_mode) != 0o700
        ):
            raise IncompleteEvidence("final_runner_attempt_archive_root_invalid")

        sources = _final_attempt_member_paths(self.artifact_directory)
        payloads: dict[str, bytes] = {}
        identities: set[tuple[int, int]] = set()
        device_identity: tuple[int, int] | None = None
        flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0)
        flags |= getattr(os, "O_NOFOLLOW", 0)
        for key, source in sources.items():
            try:
                path_metadata = source.lstat()
                descriptor = os.open(source, flags)
            except OSError as error:
                raise IncompleteEvidence(
                    f"final_runner_attempt_02_{key}_source_invalid"
                ) from error
            try:
                descriptor_metadata = os.fstat(descriptor)
                identity = (
                    descriptor_metadata.st_dev,
                    descriptor_metadata.st_ino,
                )
                required_mode = 0o644 if key == "deviceLogSha256" else 0o600
                if (
                    not stat.S_ISREG(path_metadata.st_mode)
                    or not stat.S_ISREG(descriptor_metadata.st_mode)
                    or identity != (path_metadata.st_dev, path_metadata.st_ino)
                    or identity in identities
                    or descriptor_metadata.st_nlink != 1
                    or stat.S_IMODE(descriptor_metadata.st_mode) != required_mode
                ):
                    raise IncompleteEvidence(
                        f"final_runner_attempt_02_{key}_source_invalid"
                    )
                payload = ManualTraceTransaction._read_descriptor(descriptor)
            finally:
                os.close(descriptor)
            if _sha256_bytes(payload) != FINAL_ATTEMPT_02_HASHES[key]:
                raise IncompleteEvidence(
                    f"final_runner_attempt_02_{key}_source_changed"
                )
            identities.add(identity)
            if key == "deviceLogSha256":
                device_identity = identity
            payloads[key] = payload

        failure = self.artifact_directory / TRACE_FAILURE_NAME
        _require_private_regular(failure, "final_runner_retained_failure_invalid")
        if _sha256_file(failure) != FINAL_ATTEMPT_FAILURE_SHA256:
            raise IncompleteEvidence("final_runner_retained_failure_changed")

        device_log = sources["deviceLogSha256"]
        try:
            descriptor = os.open(device_log, flags)
        except OSError as error:
            raise IncompleteEvidence(
                "final_runner_attempt_02_device_log_hardening_failed"
            ) from error
        try:
            before = os.fstat(descriptor)
            before_payload = ManualTraceTransaction._read_descriptor(descriptor)
            if (
                (before.st_dev, before.st_ino) != device_identity
                or stat.S_IMODE(before.st_mode) != 0o644
                or before_payload != payloads["deviceLogSha256"]
            ):
                raise IncompleteEvidence(
                    "final_runner_attempt_02_device_log_changed_before_hardening"
                )
            os.fchmod(descriptor, 0o600)
            os.fsync(descriptor)
            after = os.fstat(descriptor)
            after_payload = ManualTraceTransaction._read_descriptor(descriptor)
            if (
                (after.st_dev, after.st_ino) != device_identity
                or stat.S_IMODE(after.st_mode) != 0o600
                or after_payload != before_payload
                or _sha256_bytes(after_payload)
                != FINAL_ATTEMPT_02_HASHES["deviceLogSha256"]
            ):
                raise IncompleteEvidence(
                    "final_runner_attempt_02_device_log_hardening_changed_bytes"
                )
        except OSError as error:
            raise IncompleteEvidence(
                "final_runner_attempt_02_device_log_hardening_failed"
            ) from error
        finally:
            os.close(descriptor)
        os.chmod(device_log, 0o600)
        _fsync_directory(device_log.parent)

        try:
            attempt_02.mkdir(mode=0o700)
            os.chmod(attempt_02, 0o700)
            _fsync_directory(archive_root)
        except OSError as error:
            raise IncompleteEvidence(
                "final_runner_attempt_02_archive_create_failed"
            ) from error
        archive_members = _final_attempt_member_paths(attempt_02)
        for key, destination in archive_members.items():
            _write_no_replace(
                destination,
                payloads[key],
                private=True,
                code=f"final_runner_attempt_02_{key}_archive_collision",
            )
        receipt_payload = {
            "schema": FINAL_MANUAL_PRECLAIM_ARCHIVE_SCHEMA,
            "attempt": "attempt-02",
            "authorizationId": FINAL_ATTEMPT_AUTHORIZATION,
            "priorAttempt": "attempt-01",
            "priorAttemptReceiptSha256": FINAL_ATTEMPT_01_RECEIPT_SHA256,
            "priorAttemptEntitySha256": attempt_01["entitySha256"],
            **FINAL_ATTEMPT_02_HASHES,
        }
        _write_no_replace(
            attempt_02 / "receipt.json",
            _canonical_json(receipt_payload),
            private=True,
            code="final_runner_attempt_02_receipt_collision",
        )
        evidence = _validate_fixed_final_attempt_evidence(
            self.artifact_directory
        )
        for key, source in sources.items():
            _require_private_regular(
                source, f"final_runner_attempt_02_{key}_source_changed"
            )
            if (
                source.read_bytes() != payloads[key]
                or _sha256_file(source) != FINAL_ATTEMPT_02_HASHES[key]
            ):
                raise IncompleteEvidence(
                    f"final_runner_attempt_02_{key}_source_changed"
                )
        if _validate_fixed_final_attempt_01(self.artifact_directory) != attempt_01:
            raise IncompleteEvidence("final_runner_attempt_01_changed")
        if _sha256_file(failure) != FINAL_ATTEMPT_FAILURE_SHA256:
            raise IncompleteEvidence("final_runner_retained_failure_changed")
        _event("final_runner_attempt_02_receipt")
        return evidence

    def _decode_plist_result(
        self,
        result: subprocess.CompletedProcess[str],
        code: str,
    ) -> dict[str, Any]:
        raw = result.stdout.strip()
        if not raw:
            combined = f"{result.stdout}\n{result.stderr}"
            marker = combined.find("<?xml")
            if marker >= 0:
                raw = combined[marker:].strip()
        try:
            value = plistlib.loads(raw.encode("utf-8"))
        except (ValueError, TypeError, UnicodeError) as error:
            raise IncompleteEvidence(code) from error
        if not isinstance(value, dict):
            raise IncompleteEvidence(code)
        return value

    def _attest_product(self, product_path: Path | None = None) -> dict[str, Any]:
        product_path = self.product if product_path is None else product_path
        parent = product_path.parent
        candidates = list(parent.glob("Runner.app")) if parent.is_dir() else []
        if candidates != [product_path] or product_path.is_symlink():
            raise IncompleteEvidence("final_runner_product_not_unique")
        entity_sha = _entity_digest(product_path)
        application_sha = _application_digest(product_path)

        files: dict[str, str] = {}
        for entry in sorted(
            product_path.rglob("*"),
            key=lambda value: value.relative_to(product_path).as_posix(),
        ):
            if entry.is_symlink():
                raise IncompleteEvidence("final_runner_product_contains_symlink")
            if entry.is_file():
                files[entry.relative_to(product_path).as_posix()] = _sha256_file(
                    entry
                )
        if not files:
            raise IncompleteEvidence("final_runner_product_files_missing")

        info_path = product_path / "Info.plist"
        executable_path = product_path / "Runner"
        profile_path = product_path / "embedded.mobileprovision"
        for path, code in (
            (info_path, "final_runner_info_plist_invalid"),
            (executable_path, "final_runner_executable_invalid"),
            (profile_path, "final_runner_profile_invalid"),
        ):
            if path.is_symlink() or not path.is_file():
                raise IncompleteEvidence(code)
        try:
            with info_path.open("rb") as source:
                info = plistlib.load(source)
        except (OSError, ValueError) as error:
            raise IncompleteEvidence("final_runner_info_plist_invalid") from error
        if not isinstance(info, dict):
            raise IncompleteEvidence("final_runner_info_plist_invalid")
        bundle = info.get("CFBundleIdentifier")
        executable = info.get("CFBundleExecutable")
        short_version = info.get("CFBundleShortVersionString")
        bundle_version = info.get("CFBundleVersion")
        if (
            bundle != FINAL_RUNNER_BUNDLE_ID
            or executable != "Runner"
            or not isinstance(short_version, str)
            or not short_version
            or not isinstance(bundle_version, str)
            or not bundle_version
        ):
            raise IncompleteEvidence("final_runner_info_plist_binding_invalid")

        verify_argv = [
            "codesign",
            "--verify",
            "--deep",
            "--strict",
            "--verbose=2",
            str(product_path.resolve()),
        ]
        _run_command(
            verify_argv,
            cwd=self.project_root,
            code="final_runner_codesign_verify",
        )
        metadata_argv = [
            "codesign",
            "-dv",
            "--verbose=4",
            str(product_path.resolve()),
        ]
        metadata = _run_command(
            metadata_argv,
            cwd=self.project_root,
            code="final_runner_codesign_metadata",
        )
        combined = f"{metadata.stdout}\n{metadata.stderr}"
        identifiers = re.findall(r"(?m)^Identifier=([^\r\n]+)$", combined)
        teams = re.findall(r"(?m)^TeamIdentifier=([^\r\n]+)$", combined)
        if (
            identifiers != [FINAL_RUNNER_BUNDLE_ID]
            or len(teams) != 1
            or re.fullmatch(r"[A-Z0-9]{10}", teams[0]) is None
        ):
            raise IncompleteEvidence("final_runner_codesign_identity_invalid")
        team = teams[0]

        entitlements_argv = [
            "codesign",
            "-d",
            "--entitlements",
            ":-",
            "--xml",
            str(product_path.resolve()),
        ]
        entitlements_result = _run_command(
            entitlements_argv,
            cwd=self.project_root,
            code="final_runner_codesign_entitlements",
        )
        entitlements = self._decode_plist_result(
            entitlements_result, "final_runner_signed_entitlements_invalid"
        )
        application_identifier = f"{team}.{FINAL_RUNNER_BUNDLE_ID}"
        if (
            entitlements.get("aps-environment") != "production"
            or entitlements.get("application-identifier")
            != application_identifier
            or entitlements.get("com.apple.developer.team-identifier") != team
        ):
            raise IncompleteEvidence("final_runner_signed_entitlements_invalid")
        canonical_entitlements = plistlib.dumps(
            entitlements, fmt=plistlib.FMT_BINARY, sort_keys=True
        )

        profile_argv = [
            "security",
            "cms",
            "-D",
            "-i",
            str(profile_path.resolve()),
        ]
        profile_result = _run_command(
            profile_argv,
            cwd=self.project_root,
            code="final_runner_profile_decode",
        )
        profile = self._decode_plist_result(
            profile_result, "final_runner_profile_plist_invalid"
        )
        profile_teams = profile.get("TeamIdentifier")
        profile_entitlements = profile.get("Entitlements")
        expiration = profile.get("ExpirationDate")
        certificates = profile.get("DeveloperCertificates")
        if (
            profile_teams != [team]
            or not isinstance(profile_entitlements, dict)
            or profile_entitlements.get("application-identifier")
            != application_identifier
            or profile_entitlements.get("com.apple.developer.team-identifier")
            != team
            or profile_entitlements.get("aps-environment") != "production"
            or not isinstance(expiration, dt.datetime)
            or not isinstance(certificates, list)
            or not certificates
            or not all(isinstance(value, bytes) and value for value in certificates)
        ):
            raise IncompleteEvidence("final_runner_profile_binding_invalid")
        expiration_utc = expiration
        if expiration_utc.tzinfo is None:
            expiration_utc = expiration_utc.replace(tzinfo=dt.timezone.utc)
        else:
            expiration_utc = expiration_utc.astimezone(dt.timezone.utc)
        if expiration_utc <= dt.datetime.now(dt.timezone.utc):
            raise IncompleteEvidence("final_runner_profile_expired")
        expiration_text = expiration_utc.isoformat().replace("+00:00", "Z")

        return {
            "relativePath": product_path.relative_to(self.project_root).as_posix(),
            "entitySha256": entity_sha,
            "applicationSha256": application_sha,
            "fileSha256": files,
            "runnerExecutableSha256": files["Runner"],
            "infoPlistSha256": files["Info.plist"],
            "bundleIdentifier": bundle,
            "executableName": executable,
            "bundleShortVersion": short_version,
            "bundleVersion": bundle_version,
            "configuration": "Release",
            "codesignVerifyArgv": verify_argv,
            "codesignMetadataArgv": metadata_argv,
            "codesignEntitlementsArgv": entitlements_argv,
            "profileDecodeArgv": profile_argv,
            "signedIdentifier": identifiers[0],
            "signedTeamIdentifier": team,
            "canonicalSignedEntitlementsSha256": _sha256_bytes(
                canonical_entitlements
            ),
            "embeddedMobileProvisionSha256": files[
                "embedded.mobileprovision"
            ],
            "profileTeamIdentifier": team,
            "profileApplicationIdentifier": application_identifier,
            "profileExpirationUtc": expiration_text,
            "developerCertificateSha256": sorted(
                _sha256_bytes(value) for value in certificates
            ),
        }

    @staticmethod
    def _product_copy_identity(product: Mapping[str, Any]) -> dict[str, Any]:
        excluded = {
            "relativePath",
            "entitySha256",
            "codesignVerifyArgv",
            "codesignMetadataArgv",
            "codesignEntitlementsArgv",
            "profileDecodeArgv",
        }
        return {
            key: value for key, value in product.items() if key not in excluded
        }

    def _retain_authorized_retry_product(self) -> dict[str, Any]:
        """Publish one private, attempt-scoped app and attest that exact copy."""

        if not self.authorized_retry:
            return self._attest_product()
        source_before = self._attest_product(self.build_product)
        if _path_present(self.product):
            raise IncompleteEvidence(
                "final_runner_retry_retained_product_collision"
            )
        try:
            self.product.mkdir(mode=0o700)
            os.chmod(self.product, 0o700)
            _fsync_directory(self.namespace)
        except FileExistsError as error:
            raise IncompleteEvidence(
                "final_runner_retry_retained_product_collision"
            ) from error
        except OSError as error:
            raise IncompleteEvidence(
                "final_runner_retry_retained_product_publish_failed"
            ) from error

        # The exclusive destination root is the publication boundary.  Every
        # descendant is also created no-replace; an interrupted/partial tree
        # deliberately consumes this literal attempt and can never be resumed
        # or replaced.  Only the terminal build receipt makes it installable.
        for entry in sorted(
            self.build_product.rglob("*"),
            key=lambda value: value.relative_to(
                self.build_product
            ).as_posix(),
        ):
            relative = entry.relative_to(self.build_product)
            destination = self.product / relative
            try:
                if entry.is_symlink():
                    raise IncompleteEvidence(
                        "final_runner_retry_retained_product_contains_symlink"
                    )
                if entry.is_dir():
                    destination.mkdir(mode=0o700)
                    os.chmod(destination, 0o700)
                    _fsync_directory(destination.parent)
                elif entry.is_file():
                    source_mode = stat.S_IMODE(entry.stat().st_mode)
                    _write_no_replace(
                        destination,
                        entry.read_bytes(),
                        private=True,
                        code=(
                            "final_runner_retry_retained_product_member_collision"
                        ),
                    )
                    os.chmod(
                        destination,
                        0o700 if source_mode & 0o111 else 0o600,
                    )
                    _fsync_directory(destination.parent)
                else:
                    raise IncompleteEvidence(
                        "final_runner_retry_retained_product_type_invalid"
                    )
            except FileExistsError as error:
                raise IncompleteEvidence(
                    "final_runner_retry_retained_product_member_collision"
                ) from error
            except OSError as error:
                raise IncompleteEvidence(
                    "final_runner_retry_retained_product_publish_failed"
                ) from error
        for directory in sorted(
            (entry for entry in self.product.rglob("*") if entry.is_dir()),
            key=lambda value: len(value.parts),
            reverse=True,
        ):
            _fsync_directory(directory)
        _fsync_directory(self.product)
        _fsync_directory(self.namespace)

        source_after = self._attest_product(self.build_product)
        retained = self._attest_product(self.product)
        if (
            source_after != source_before
            or self._product_copy_identity(retained)
            != self._product_copy_identity(source_before)
        ):
            raise IncompleteEvidence(
                "final_runner_retry_retained_product_binding_invalid"
            )
        return retained

    def prepare(self) -> int:
        self._validate_fixed_scope()
        self._validate_build_values()
        self._assert_trace_quiescent()
        self._preflight_prepare_namespace()
        retry_authority_before = self._authorized_retry_authority()
        evidence_before = (
            retry_authority_before["evidence"]
            if retry_authority_before is not None
            else self._seal_attempt_02()
        )
        source_before = _suite_source_digest(self.project_root)
        self._ensure_namespace(expected_names=set())
        build_argv = self._build_argv(self.build_name, self.build_number)
        xcode_build_settings = dict(FINAL_RUNNER_XCODE_BUILD_SETTINGS)
        claim = {
            "schema": FINAL_RUNNER_BUILD_CLAIM_SCHEMA,
            "authorizationId": self.expected_authorization,
            "recipient": FINAL_RUNNER_RECIPIENT,
            "bundleIdentifier": FINAL_RUNNER_BUNDLE_ID,
            "artifactDirectoryRelativePath": FINAL_RUNNER_ARTIFACT_RELATIVE.as_posix(),
            "namespaceRelativePath": (
                FINAL_RUNNER_ARTIFACT_RELATIVE / self.namespace_name
            ).as_posix(),
            "configuration": "Release",
            "buildName": self.build_name,
            "buildNumber": self.build_number,
            "buildArgv": build_argv,
            "xcodeBuildSettings": xcode_build_settings,
            "suiteSourceDigestBefore": source_before,
            "evidence": evidence_before,
            **self._retry_receipt_fields(retry_authority_before),
        }
        _write_no_replace(
            self.build_claim,
            _canonical_json(claim),
            private=True,
            code="final_runner_build_claim_collision",
        )
        claim_sha = _sha256_file(self.build_claim)
        receipt_common = {
            "schema": FINAL_RUNNER_BUILD_RECEIPT_SCHEMA,
            "authorizationId": self.expected_authorization,
            "recipient": FINAL_RUNNER_RECIPIENT,
            "bundleIdentifier": FINAL_RUNNER_BUNDLE_ID,
            "claimSha256": claim_sha,
            "configuration": "Release",
            "buildName": self.build_name,
            "buildNumber": self.build_number,
            "buildArgv": build_argv,
            "xcodeBuildSettings": xcode_build_settings,
            "suiteSourceDigestBefore": source_before,
            **self._retry_receipt_fields(retry_authority_before),
        }
        try:
            _event("final_runner_build_command")
            _run_command(
                build_argv,
                cwd=self.project_root,
                environment=FINAL_RUNNER_FLUTTER_BUILD_ENVIRONMENT,
                remove_environment=FINAL_RUNNER_BUILD_ENVIRONMENT_REMOVALS,
                remove_environment_prefixes=(
                    FINAL_RUNNER_BUILD_ENVIRONMENT_PREFIX_REMOVALS
                ),
                code="final_runner_build_command",
            )
            source_after = _suite_source_digest(self.project_root)
            if source_after != source_before:
                raise IncompleteEvidence("final_runner_source_changed_during_build")
            retry_authority_after = self._authorized_retry_authority()
            evidence_after = (
                retry_authority_after["evidence"]
                if retry_authority_after is not None
                else _validate_fixed_final_attempt_evidence(
                    self.artifact_directory
                )
            )
            if evidence_after != evidence_before:
                raise IncompleteEvidence("final_runner_evidence_changed_during_build")
            if retry_authority_after != retry_authority_before:
                raise IncompleteEvidence(
                    "final_runner_retry_authority_changed_during_build"
                )
            product = self._retain_authorized_retry_product()
            if self._authorized_retry_authority() != retry_authority_before:
                raise IncompleteEvidence(
                    "final_runner_retry_authority_changed_during_retention"
                )
            if (
                product["bundleShortVersion"] != self.build_name
                or product["bundleVersion"] != self.build_number
            ):
                raise IncompleteEvidence("final_runner_built_version_mismatch")
            terminal = {
                **receipt_common,
                "status": "succeeded",
                "suiteSourceDigestAfter": source_after,
                "evidence": evidence_after,
                "product": product,
            }
        except BaseException as error:
            failure = self._typed_failure(error, "final_runner_build_failed")
            terminal = {
                **receipt_common,
                "status": "failed",
                "failure": failure,
            }
            _write_no_replace(
                self.build_receipt,
                _canonical_json(terminal),
                private=True,
                code="final_runner_build_receipt_collision",
            )
            if isinstance(error, (InterruptedTransaction, KeyboardInterrupt)):
                raise
            raise IncompleteEvidence(failure) from error
        _write_no_replace(
            self.build_receipt,
            _canonical_json(terminal),
            private=True,
            code="final_runner_build_receipt_collision",
        )
        print("FINAL_RUNNER_BUILD_READY: signed Release product sealed.")
        return 0

    def _validate_build_state(self) -> tuple[dict[str, Any], dict[str, Any]]:
        expected_names = {
            FINAL_RUNNER_BUILD_CLAIM_NAME,
            FINAL_RUNNER_BUILD_RECEIPT_NAME,
        }
        if self.authorized_retry:
            expected_names.add(FINAL_RUNNER_AUTHORIZED_RETRY_PRODUCT_NAME)
        self._ensure_namespace(expected_names=expected_names)
        _require_private_regular(
            self.build_claim, "final_runner_build_claim_invalid"
        )
        _require_private_regular(
            self.build_receipt, "final_runner_build_receipt_invalid"
        )
        claim = _read_json(self.build_claim, "final_runner_build_claim_invalid")
        receipt = _read_json(
            self.build_receipt, "final_runner_build_receipt_invalid"
        )
        if (
            claim.get("schema") != FINAL_RUNNER_BUILD_CLAIM_SCHEMA
            or receipt.get("schema") != FINAL_RUNNER_BUILD_RECEIPT_SCHEMA
            or receipt.get("status") != "succeeded"
            or claim.get("authorizationId") != self.expected_authorization
            or receipt.get("authorizationId") != self.expected_authorization
            or claim.get("recipient") != FINAL_RUNNER_RECIPIENT
            or receipt.get("recipient") != FINAL_RUNNER_RECIPIENT
            or claim.get("bundleIdentifier") != FINAL_RUNNER_BUNDLE_ID
            or receipt.get("bundleIdentifier") != FINAL_RUNNER_BUNDLE_ID
            or receipt.get("claimSha256") != _sha256_file(self.build_claim)
            or claim.get("artifactDirectoryRelativePath")
            != FINAL_RUNNER_ARTIFACT_RELATIVE.as_posix()
            or claim.get("namespaceRelativePath")
            != (FINAL_RUNNER_ARTIFACT_RELATIVE / self.namespace_name).as_posix()
        ):
            raise IncompleteEvidence("final_runner_build_receipt_binding_invalid")
        build_name = receipt.get("buildName")
        build_number = receipt.get("buildNumber")
        if (
            not isinstance(build_name, str)
            or not isinstance(build_number, str)
            or receipt.get("configuration") != "Release"
            or receipt.get("buildArgv")
            != self._build_argv(build_name, build_number)
            or claim.get("buildArgv") != receipt.get("buildArgv")
            or receipt.get("xcodeBuildSettings")
            != FINAL_RUNNER_XCODE_BUILD_SETTINGS
            or claim.get("xcodeBuildSettings")
            != receipt.get("xcodeBuildSettings")
        ):
            raise IncompleteEvidence("final_runner_build_argv_binding_invalid")
        source = _suite_source_digest(self.project_root)
        if (
            claim.get("suiteSourceDigestBefore") != source
            or receipt.get("suiteSourceDigestBefore") != source
            or receipt.get("suiteSourceDigestAfter") != source
        ):
            raise IncompleteEvidence("final_runner_source_changed_after_build")
        retry_authority = self._authorized_retry_authority()
        evidence = (
            retry_authority["evidence"]
            if retry_authority is not None
            else _validate_fixed_final_attempt_evidence(
                self.artifact_directory
            )
        )
        if claim.get("evidence") != evidence or receipt.get("evidence") != evidence:
            raise IncompleteEvidence("final_runner_evidence_changed_after_build")
        if self.authorized_retry:
            if (
                claim.get("attemptNamespace")
                != FINAL_RUNNER_AUTHORIZED_RETRY_ATTEMPT
                or receipt.get("attemptNamespace")
                != FINAL_RUNNER_AUTHORIZED_RETRY_ATTEMPT
                or claim.get("retryAuthority") != retry_authority
                or receipt.get("retryAuthority") != retry_authority
            ):
                raise IncompleteEvidence(
                    "final_runner_retry_build_receipt_binding_invalid"
                )
        elif any(
            key in value
            for value in (claim, receipt)
            for key in ("attemptNamespace", "retryAuthority")
        ):
            raise IncompleteEvidence(
                "final_runner_build_receipt_namespace_mixed"
            )
        product = self._attest_product()
        if receipt.get("product") != product:
            raise IncompleteEvidence("final_runner_product_changed_after_build")
        if (
            product["bundleShortVersion"] != build_name
            or product["bundleVersion"] != build_number
        ):
            raise IncompleteEvidence("final_runner_product_version_changed")
        return receipt, product

    def _run_read_only_command(
        self,
        command: Sequence[str],
        *,
        code: str,
        allow_failure: bool = False,
        input_text: str | None = None,
    ) -> subprocess.CompletedProcess[str]:
        try:
            result = subprocess.run(
                list(command),
                cwd=self.project_root,
                env=os.environ.copy(),
                text=True,
                input=input_text,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
        except OSError as error:
            raise IncompleteEvidence(f"{code}_launch_failed") from error
        if result.returncode != 0 and not allow_failure:
            raise IncompleteEvidence(f"{code}_failed")
        return result

    @staticmethod
    def _afc_integer(
        value: Any,
        *,
        phase: str,
        field: str,
        positive: bool,
    ) -> int:
        if isinstance(value, bool):
            raise IncompleteEvidence(
                f"final_runner_{phase}_afc_{field}_invalid"
            )
        if isinstance(value, int):
            normalized = value
        elif isinstance(value, str) and re.fullmatch(r"[0-9]+", value):
            normalized = int(value)
        else:
            raise IncompleteEvidence(
                f"final_runner_{phase}_afc_{field}_invalid"
            )
        if normalized < 0 or (positive and normalized == 0):
            raise IncompleteEvidence(
                f"final_runner_{phase}_afc_{field}_invalid"
            )
        return normalized

    @staticmethod
    def _decode_afc_metadata(raw: str, phase: str) -> list[dict[str, Any]]:
        candidates: list[Any] = []
        try:
            decoded = json.loads(raw)
        except (json.JSONDecodeError, TypeError, ValueError):
            decoder = json.JSONDecoder()
            position = 0
            while position < len(raw):
                opening = raw.find("{", position)
                if opening < 0:
                    break
                try:
                    decoded, consumed = decoder.raw_decode(raw[opening:])
                except json.JSONDecodeError:
                    position = opening + 1
                    continue
                candidates.append(decoded)
                position = opening + consumed
        else:
            if isinstance(decoded, list):
                candidates.extend(decoded)
            else:
                candidates.append(decoded)
        metadata = [
            value
            for value in candidates
            if isinstance(value, dict)
            and "st_ifmt" in value
            and "st_birthtime" in value
        ]
        if len(metadata) != 2:
            raise IncompleteEvidence(f"final_runner_{phase}_afc_metadata_invalid")
        return metadata

    def _afc_metadata_sample(self, phase: str) -> dict[str, Any]:
        command = [
            "afcclient",
            "-u",
            FINAL_RUNNER_RECIPIENT,
            "--container",
            FINAL_RUNNER_BUNDLE_ID,
        ]
        result = self._run_read_only_command(
            command,
            code=f"final_runner_{phase}_afc_metadata",
            input_text="info /\ninfo Documents/identity.db\nquit\n",
        )
        root, database = self._decode_afc_metadata(result.stdout.strip(), phase)
        if root.get("st_ifmt") != "S_IFDIR":
            raise IncompleteEvidence(f"final_runner_{phase}_afc_root_invalid")
        if database.get("st_ifmt") != "S_IFREG":
            raise IncompleteEvidence(
                f"final_runner_{phase}_identity_db_type_invalid"
            )
        root_birthtime = self._afc_integer(
            root.get("st_birthtime"),
            phase=phase,
            field="root_birthtime",
            positive=True,
        )
        database_birthtime = self._afc_integer(
            database.get("st_birthtime"),
            phase=phase,
            field="identity_db_birthtime",
            positive=True,
        )
        database_nlink = self._afc_integer(
            database.get("st_nlink"),
            phase=phase,
            field="identity_db_nlink",
            positive=True,
        )
        database_size = self._afc_integer(
            database.get("st_size"),
            phase=phase,
            field="identity_db_size",
            positive=True,
        )
        database_mtime = self._afc_integer(
            database.get("st_mtime"),
            phase=phase,
            field="identity_db_mtime",
            positive=False,
        )
        if database_nlink != 1:
            raise IncompleteEvidence(
                f"final_runner_{phase}_identity_db_nlink_invalid"
            )
        database_sha = self._copy_remote_file_sha256(
            "Documents/identity.db", phase=phase
        )
        return {
            "afcRoot": {
                "path": "/",
                "st_ifmt": "S_IFDIR",
                "st_birthtime": root_birthtime,
            },
            "identityDatabase": {
                "path": "Documents/identity.db",
                "st_ifmt": "S_IFREG",
                "st_birthtime": database_birthtime,
                "diagnostics": {
                    "st_nlink": database_nlink,
                    "st_size": database_size,
                    "st_mtime": database_mtime,
                    "sha256": database_sha,
                },
            },
        }

    def _inventory(self, phase: str) -> dict[str, Any]:
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{phase}-inventory.", dir=self.namespace
        )
        temporary = Path(temporary_name)
        try:
            os.fchmod(descriptor, 0o600)
            os.close(descriptor)
            command = [
                "xcrun",
                "devicectl",
                "device",
                "info",
                "apps",
                "--device",
                FINAL_RUNNER_RECIPIENT,
                "--bundle-id",
                FINAL_RUNNER_BUNDLE_ID,
                "--json-output",
                str(temporary),
                "--timeout",
                "60",
            ]
            self._run_read_only_command(
                command, code=f"final_runner_{phase}_inventory"
            )
            _require_private_regular(
                temporary, f"final_runner_{phase}_inventory_not_private"
            )
            if temporary.stat().st_size <= 0 or temporary.stat().st_size > 4 * 1024 * 1024:
                raise IncompleteEvidence(f"final_runner_{phase}_inventory_size_invalid")
            value = _read_json(
                temporary, f"final_runner_{phase}_inventory_invalid"
            )
        finally:
            try:
                os.close(descriptor)
            except OSError:
                pass
            if temporary.exists():
                temporary.unlink()
        result = value.get("result")
        apps = result.get("apps") if isinstance(result, dict) else None
        if not isinstance(apps, list):
            raise IncompleteEvidence(f"final_runner_{phase}_inventory_invalid")
        matches = [
            app
            for app in apps
            if isinstance(app, dict)
            and app.get("bundleIdentifier") == FINAL_RUNNER_BUNDLE_ID
        ]
        if len(matches) != 1:
            raise IncompleteEvidence(f"final_runner_{phase}_app_not_unique")
        app = matches[0]
        bundle = app.get("bundleIdentifier")
        if bundle != FINAL_RUNNER_BUNDLE_ID:
            raise IncompleteEvidence(
                f"final_runner_{phase}_bundleIdentifier_invalid"
            )
        legacy_version = app.get("bundleShortVersion")
        current_version = app.get("version")
        versions = [
            entry
            for entry in (legacy_version, current_version)
            if entry is not None
        ]
        if (
            not versions
            or any(
                not isinstance(entry, str) or not entry or "\n" in entry
                for entry in versions
            )
            or len(set(versions)) != 1
        ):
            raise IncompleteEvidence(
                f"final_runner_{phase}_bundleShortVersion_invalid"
            )
        short_version = versions[0]
        bundle_version = app.get("bundleVersion")
        if (
            not isinstance(bundle_version, str)
            or not bundle_version
            or "\n" in bundle_version
        ):
            raise IncompleteEvidence(
                f"final_runner_{phase}_bundleVersion_invalid"
            )
        app_url = app.get("url")
        if (
            not isinstance(app_url, str)
            or not app_url
            or "\n" in app_url
            or "<" in app_url
            or ">" in app_url
        ):
            raise IncompleteEvidence(f"final_runner_{phase}_url_invalid")
        literal_app_path = (
            app_url[7:] if app_url.startswith("file://") else app_url
        ).rstrip("/")
        if (
            not literal_app_path.startswith("/")
            or Path(literal_app_path).name != "Runner.app"
        ):
            raise IncompleteEvidence(f"final_runner_{phase}_url_invalid")
        derived_executable = Path(literal_app_path).stem
        executable = app.get("executableName", derived_executable)
        if (
            not isinstance(executable, str)
            or executable != derived_executable
        ):
            raise IncompleteEvidence(f"final_runner_{phase}_executable_invalid")
        if "appDataContainer" in app:
            container = app.get("appDataContainer")
            if (
                not isinstance(container, str)
                or not container
                or "\n" in container
            ):
                raise IncompleteEvidence(
                    f"final_runner_{phase}_appDataContainer_invalid"
                )
            literal_container_path = (
                container[7:] if container.startswith("file://") else container
            )
            if (
                not literal_container_path.startswith("/")
                or "<private>" in container
                or "<" in container
                or ">" in container
            ):
                raise IncompleteEvidence("final_runner_data_container_not_literal")
        else:
            container = None
        return {
            "bundleIdentifier": bundle,
            "bundleShortVersion": short_version,
            "bundleVersion": bundle_version,
            "executableName": executable,
            "appDataContainer": container,
            "url": app_url,
        }

    def _copy_remote_file_sha256(self, relative: str, *, phase: str) -> str:
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{phase}-{Path(relative).name}.",
            dir=self.namespace,
        )
        temporary = Path(temporary_name)
        try:
            os.fchmod(descriptor, 0o600)
            os.close(descriptor)
            if stat.S_IMODE(temporary.stat().st_mode) != 0o600:
                raise IncompleteEvidence("final_runner_identity_temp_not_private")
            command = [
                "xcrun",
                "devicectl",
                "device",
                "copy",
                "from",
                "--device",
                FINAL_RUNNER_RECIPIENT,
                "--source",
                relative,
                "--destination",
                str(temporary),
                "--domain-type",
                "appDataContainer",
                "--domain-identifier",
                FINAL_RUNNER_BUNDLE_ID,
                "--timeout",
                "15",
            ]
            result = self._run_read_only_command(
                command,
                code=f"final_runner_{phase}_{Path(relative).name}_copy_from",
            )
            if temporary.is_symlink() or not temporary.is_file():
                raise IncompleteEvidence(
                    f"final_runner_{phase}_diagnostic_copy_invalid"
                )
            os.chmod(temporary, 0o600)
            _require_private_regular(
                temporary,
                f"final_runner_{phase}_diagnostic_copy_not_private",
            )
            if temporary.stat().st_size <= 0:
                raise IncompleteEvidence(
                    f"final_runner_{phase}_diagnostic_copy_empty"
                )
            return _sha256_file(temporary)
        finally:
            try:
                os.close(descriptor)
            except OSError:
                pass
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass

    def _continuity_sample(self, phase: str) -> dict[str, Any]:
        inventory = self._inventory(phase)
        afc = self._afc_metadata_sample(phase)
        sample = {
            "recipient": FINAL_RUNNER_RECIPIENT,
            "bundleIdentifier": FINAL_RUNNER_BUNDLE_ID,
            "inventory": inventory,
            **afc,
        }
        _continuity_stable_fields(
            sample, f"final_runner_{phase}_continuity_sample_invalid"
        )
        return sample

    def install(self) -> int:
        self._validate_fixed_scope()
        self._assert_trace_quiescent()
        build_receipt, product = self._validate_build_state()
        retry_authority = self._authorized_retry_authority()
        evidence = (
            retry_authority["evidence"]
            if retry_authority is not None
            else _validate_fixed_final_attempt_evidence(
                self.artifact_directory
            )
        )
        lock = _acquire_transaction_lock(
            self.project_root / "build/plan398/diagnostic-transaction.lock"
        )
        try:
            self._assert_trace_quiescent()
            build_receipt, product = self._validate_build_state()
            pre_samples = [
                self._continuity_sample("pre-1"),
                self._continuity_sample("pre-2"),
            ]
            first_pre_fields = _continuity_stable_fields(
                pre_samples[0], "final_runner_preinstall_continuity_invalid"
            )
            second_pre_fields = _continuity_stable_fields(
                pre_samples[1], "final_runner_preinstall_continuity_invalid"
            )
            if (
                first_pre_fields != second_pre_fields
                or pre_samples[0]["inventory"] != pre_samples[1]["inventory"]
            ):
                raise IncompleteEvidence(
                    "final_runner_preinstall_continuity_unstable"
                )
            pre_inventory = pre_samples[1]["inventory"]
            pre_version = pre_inventory["bundleShortVersion"]
            pre_build = pre_inventory["bundleVersion"]
            if (
                pre_version == product["bundleShortVersion"]
                and pre_build == product["bundleVersion"]
            ):
                raise IncompleteEvidence(
                    "final_runner_product_already_installed"
                )
            if (
                re.fullmatch(r"[0-9]+(?:\.[0-9]+){2}", pre_version) is None
                or re.fullmatch(r"[1-9][0-9]{0,17}", pre_build) is None
                or tuple(int(value) for value in product["bundleShortVersion"].split("."))
                <= tuple(int(value) for value in pre_version.split("."))
                or int(product["bundleVersion"]) <= int(pre_build)
            ):
                raise IncompleteEvidence("final_runner_product_not_newer")
            self._assert_trace_quiescent()
            revalidated_receipt, revalidated_product = self._validate_build_state()
            if (
                revalidated_receipt != build_receipt
                or revalidated_product != product
                or _validate_fixed_final_attempt_evidence(
                    self.artifact_directory
                )
                != evidence
                or self._authorized_retry_authority() != retry_authority
            ):
                raise IncompleteEvidence("final_runner_preinstall_binding_changed")

            install_argv = self._install_argv()
            claim = {
                "schema": FINAL_RUNNER_INSTALL_CLAIM_SCHEMA,
                "authorizationId": self.expected_authorization,
                "recipient": FINAL_RUNNER_RECIPIENT,
                "bundleIdentifier": FINAL_RUNNER_BUNDLE_ID,
                "buildClaimSha256": _sha256_file(self.build_claim),
                "buildReceiptSha256": _sha256_file(self.build_receipt),
                "productEntitySha256": product["entitySha256"],
                "productApplicationSha256": product["applicationSha256"],
                "evidence": evidence,
                "installArgv": install_argv,
                "preInventory": pre_inventory,
                "preContinuitySamples": pre_samples,
                **self._retry_receipt_fields(retry_authority),
            }
            _write_no_replace(
                self.install_claim,
                _canonical_json(claim),
                private=True,
                code="final_runner_install_claim_collision",
            )
            receipt_common: dict[str, Any] = {
                "schema": FINAL_RUNNER_INSTALL_RECEIPT_SCHEMA,
                "authorizationId": self.expected_authorization,
                "recipient": FINAL_RUNNER_RECIPIENT,
                "bundleIdentifier": FINAL_RUNNER_BUNDLE_ID,
                "claimSha256": _sha256_file(self.install_claim),
                "buildReceiptSha256": _sha256_file(self.build_receipt),
                "installArgv": install_argv,
                "preInventory": pre_inventory,
                "preContinuitySamples": pre_samples,
                **self._retry_receipt_fields(retry_authority),
            }
            try:
                _event("final_runner_install_command")
                _run_command(
                    install_argv,
                    cwd=self.project_root,
                    code="final_runner_install_command",
                )
                post_sample = self._continuity_sample("post")
                post_inventory = post_sample["inventory"]
                post_fields = _continuity_stable_fields(
                    post_sample, "final_runner_postinstall_continuity_invalid"
                )
                if (
                    post_fields["appDataContainer"]
                    != second_pre_fields["appDataContainer"]
                ):
                    raise IncompleteEvidence("final_runner_data_container_changed")
                if post_fields["afcRoot"] != second_pre_fields["afcRoot"]:
                    raise IncompleteEvidence("final_runner_afc_root_changed")
                if (
                    post_fields["identityDatabase"]
                    != second_pre_fields["identityDatabase"]
                ):
                    raise IncompleteEvidence("final_runner_identity_db_replaced")
                if (
                    post_inventory["bundleIdentifier"] != FINAL_RUNNER_BUNDLE_ID
                    or post_inventory["bundleShortVersion"]
                    != product["bundleShortVersion"]
                    or post_inventory["bundleVersion"]
                    != product["bundleVersion"]
                    or post_inventory["executableName"]
                    != product["executableName"]
                ):
                    raise IncompleteEvidence(
                        "final_runner_installed_product_binding_invalid"
                    )
                if post_inventory["url"] == pre_inventory["url"]:
                    raise IncompleteEvidence("final_runner_app_url_unchanged")
                if self.authorized_retry and (
                    self._attest_product() != product
                    or _suite_source_digest(self.project_root)
                    != build_receipt["suiteSourceDigestAfter"]
                    or self._authorized_retry_authority()
                    != retry_authority
                ):
                    raise IncompleteEvidence(
                        "final_runner_retry_binding_changed_after_install"
                    )
                terminal = {
                    **receipt_common,
                    "status": "succeeded",
                    "postInventory": post_inventory,
                    "postContinuitySample": post_sample,
                }
            except BaseException as error:
                failure = self._typed_failure(error, "final_runner_install_failed")
                terminal = {
                    **receipt_common,
                    "status": "failed",
                    "failure": failure,
                }
                _write_no_replace(
                    self.install_receipt,
                    _canonical_json(terminal),
                    private=True,
                    code="final_runner_install_receipt_collision",
                )
                if isinstance(error, (InterruptedTransaction, KeyboardInterrupt)):
                    raise
                raise IncompleteEvidence(failure) from error
            _write_no_replace(
                self.install_receipt,
                _canonical_json(terminal),
                private=True,
                code="final_runner_install_receipt_collision",
            )
            print(
                "FINAL_RUNNER_INSTALL_COMPLETE: same-container filesystem continuity sealed."
            )
            return 0
        finally:
            lock.close()


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    run = subparsers.add_parser("run")
    run.add_argument("--project-root", required=True)
    run.add_argument("--run-id", required=True)
    run.add_argument("--prior-authority", required=True)
    run.add_argument("--sender", required=True)
    run.add_argument("--recipient", required=True)
    run.add_argument("--staging-manifest", required=True)
    run.add_argument("--relay-target", required=True)
    run.add_argument("--relay-key", required=True)
    run.add_argument("--relay-addresses", required=True)
    run.add_argument("--service-account", required=True)
    run.add_argument("--single-owner", action="store_true")
    restart = subparsers.add_parser("restart-current-source")
    restart.add_argument("--project-root", required=True)
    restart.add_argument("--authorization-id", required=True)
    restart.add_argument("--retained-source-digest", required=True)
    restart.add_argument("--current-source-digest", required=True)
    prepare_runner = subparsers.add_parser("prepare-final-runner-update")
    prepare_runner.add_argument("--project-root", required=True)
    prepare_runner.add_argument("--artifact-dir", required=True)
    prepare_runner.add_argument("--authorization-id", required=True)
    prepare_runner.add_argument("--attempt-namespace")
    prepare_runner.add_argument("--recipient", required=True)
    prepare_runner.add_argument("--bundle-id", required=True)
    prepare_runner.add_argument("--build-name", required=True)
    prepare_runner.add_argument("--build-number", required=True)
    prepare_runner.add_argument("--final-attempt-journal-sha256", required=True)
    prepare_runner.add_argument("--final-attempt-device-log-sha256", required=True)
    prepare_runner.add_argument(
        "--final-attempt-trace-manifest-sha256", required=True
    )
    prepare_runner.add_argument(
        "--final-attempt-trace-relay-state-sha256", required=True
    )
    install_runner = subparsers.add_parser("install-final-runner-update")
    install_runner.add_argument("--project-root", required=True)
    install_runner.add_argument("--artifact-dir", required=True)
    install_runner.add_argument("--authorization-id", required=True)
    install_runner.add_argument("--attempt-namespace")
    install_runner.add_argument("--recipient", required=True)
    install_runner.add_argument("--bundle-id", required=True)
    manual = subparsers.add_parser("manual-trace")
    manual.add_argument("--project-root", required=True)
    manual.add_argument("--prior-authority", required=True)
    manual.add_argument("--sender", required=True)
    manual.add_argument("--recipient", required=True)
    manual.add_argument("--artifact-dir", required=True)
    manual.add_argument("--staging-manifest", required=True)
    manual.add_argument("--relay-target", required=True)
    manual.add_argument("--relay-key", required=True)
    manual.add_argument("--relay-addresses", required=True)
    manual.add_argument("--group-name", required=True)
    manual.add_argument("--existing-target-marker", required=True)
    manual.add_argument("--retained-failure-sha256")
    manual.add_argument("--live-diagnostic", action="store_true")
    manual.add_argument("--attempt-namespace")
    manual.add_argument("--prior-manual-preclaim-journal-sha256")
    manual.add_argument("--prior-manual-preclaim-device-log-sha256")
    manual.add_argument("--prior-manual-preclaim-trace-manifest-sha256")
    manual.add_argument("--prior-manual-preclaim-trace-relay-state-sha256")
    manual.add_argument("--final-attempt-authorization-id")
    manual.add_argument("--final-attempt-journal-sha256")
    manual.add_argument("--final-attempt-device-log-sha256")
    manual.add_argument("--final-attempt-trace-manifest-sha256")
    manual.add_argument("--final-attempt-trace-relay-state-sha256")
    manual.add_argument("--plan398-final-runner-product-receipt-sha256")
    manual.add_argument("--plan398-final-runner-install-terminal-sha256")
    manual.add_argument("--plan398-attempt-02-receipt-sha256")
    manual.add_argument("--single-owner", action="store_true")
    manual.set_defaults(
        run_id="existing-state-manual-trace",
        service_account=os.devnull,
    )
    subparsers.add_parser("claim-send")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.command == "claim-send":
            return claim_send()
        if args.command == "restart-current-source":
            return CurrentSourceRestart(args).run()
        if args.command == "prepare-final-runner-update":
            return FinalRunnerUpdate(args).prepare()
        if args.command == "install-final-runner-update":
            return FinalRunnerUpdate(args).install()
        if args.command == "manual-trace":
            transaction = ManualTraceTransaction(args)
            transaction.install_signal_handlers()
            return transaction.run()
        transaction = Transaction(args)
        transaction.install_signal_handlers()
        return transaction.run()
    except InterruptedTransaction as error:
        print(f"INCOMPLETE_EVIDENCE: {error}", file=sys.stderr)
        return 128 + error.signum
    except IncompleteEvidence as error:
        print(f"INCOMPLETE_EVIDENCE: {error}", file=sys.stderr)
        return 78


if __name__ == "__main__":
    raise SystemExit(main())
