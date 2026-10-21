#!/usr/bin/env python3
"""Restore one pristine database for the dedicated iOS notification campaign.

This host-only adapter closes the gap that UI automation cannot prove: exact
encrypted database bytes must survive fresh installs while the on-device
Keychain retains the fixture's keys. It never launches or uninstalls an app.
The caller installs into an absent app container, restores before first launch,
and then requires a fresh protected peer/ML-KEM handoff from the real app.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tempfile

from ios_receiver_bootstrap import (
    BUNDLE_ID,
    BootstrapBlocked,
    _DeviceControl,
)


SCHEMA = "mknoon.sims.ios-notification-identity-snapshot.v1"
RESULT_SCHEMA = "mknoon.sims.ios-notification-identity-fixture-result.v1"
RESULT_PREFIX = "IOS_NOTIFICATION_IDENTITY_FIXTURE_RESULT_JSON="
_FILES = {"identity.db", "identity.db-wal", "identity.db-shm", "identity.db-journal"}
_SHA256 = re.compile(r"^[0-9a-f]{64}$")


class FixtureFailure(Exception):
    """Only fixed, non-sensitive failure codes may leave this adapter."""


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for part in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(part)
    return digest.hexdigest()


def _private(path: Path, *, directory: bool = False) -> None:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise FixtureFailure("fixture_missing") from error
    expected = stat.S_ISDIR if directory else stat.S_ISREG
    if (
        not expected(metadata.st_mode)
        or path.is_symlink()
        or metadata.st_mode & 0o077
        or metadata.st_uid != os.getuid()
        or (not directory and metadata.st_nlink != 1)
    ):
        raise FixtureFailure("fixture_unprotected")


def _read_json(path: Path) -> dict:
    _private(path)
    try:
        if path.stat().st_size > 65536:
            raise FixtureFailure("fixture_json_oversized")
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise FixtureFailure("fixture_json_invalid") from error
    if not isinstance(value, dict):
        raise FixtureFailure("fixture_json_invalid")
    return value


def validate_fixture(staging_path: Path, *, receiver: str, peer: str) -> dict:
    """Validate every binding and byte before a device command is possible."""
    staging_path = staging_path.absolute()
    staging = _read_json(staging_path)
    if (
        staging.get("receiverDeviceId") != receiver
        or staging.get("peerDeviceId") != peer
        or staging.get("bundleId") != BUNDLE_ID
        or staging.get("dedicatedDisposableReceiver") is not True
        or staging.get("destructiveTestStateResetAuthorized") is not True
    ):
        raise FixtureFailure("staging_binding")
    reference = staging.get("identityDatabaseSnapshotManifest")
    if not isinstance(reference, str) or not reference:
        raise FixtureFailure("fixture_reference_missing")
    manifest_digest = staging.get("identityDatabaseSnapshotSha256")
    if not isinstance(manifest_digest, str) or not _SHA256.fullmatch(manifest_digest):
        raise FixtureFailure("fixture_manifest_digest_missing")
    relative = PurePosixPath(reference)
    if (
        relative.is_absolute()
        or any(part in {"", ".", ".."} for part in reference.split("/"))
        or "\\" in reference
    ):
        raise FixtureFailure("fixture_path_invalid")
    base = staging_path.parent
    path = base
    for part in relative.parts:
        path = path / part
        if path.is_symlink():
            raise FixtureFailure("fixture_path_invalid")
    try:
        path.resolve().relative_to(base.resolve())
    except ValueError as error:
        raise FixtureFailure("fixture_path_invalid") from error
    _private(path.parent, directory=True)
    manifest = _read_json(path)
    if _sha256(path) != manifest_digest:
        raise FixtureFailure("fixture_manifest_digest")
    if set(manifest) != {
        "schema", "bundleId", "receiverDeviceIdSha256", "peerDeviceIdSha256",
        "mlKemPublicKeySha256", "pristineBeforeProviderDispatch", "files",
    }:
        raise FixtureFailure("fixture_shape")
    expected = {
        "schema": SCHEMA,
        "bundleId": BUNDLE_ID,
        "receiverDeviceIdSha256": hashlib.sha256(receiver.encode()).hexdigest(),
        "peerDeviceIdSha256": hashlib.sha256(peer.encode()).hexdigest(),
        "pristineBeforeProviderDispatch": True,
    }
    if (
        any(manifest.get(key) != value for key, value in expected.items())
        or manifest.get("pristineBeforeProviderDispatch") is not True
    ):
        raise FixtureFailure("fixture_binding")
    if not _SHA256.fullmatch(str(manifest.get("mlKemPublicKeySha256", ""))):
        raise FixtureFailure("fixture_key_binding")
    files = manifest.get("files")
    if (
        not isinstance(files, dict)
        or "identity.db" not in files
        or set(files) - _FILES
        or any(not _SHA256.fullmatch(str(digest)) for digest in files.values())
    ):
        raise FixtureFailure("fixture_files")
    allowed = set(files) | {path.name}
    if {entry.name for entry in path.parent.iterdir()} != allowed:
        raise FixtureFailure("fixture_untracked_files")
    for name, digest in files.items():
        source = path.parent / name
        _private(source)
        if _sha256(source) != digest:
            raise FixtureFailure("fixture_digest")
    return {
        "manifest": path,
        "files": {name: path.parent / name for name in sorted(files)},
        "digests": dict(files),
        "manifestSha256": _sha256(path),
        "mlKemPublicKeySha256": manifest["mlKemPublicKeySha256"],
    }


def restore_fixture(staging_path: Path, *, receiver: str, peer: str,
                    control=None, temporary: Path) -> dict:
    fixture = validate_fixture(staging_path, receiver=receiver, peer=peer)
    if control is None:
        control = _DeviceControl(receiver=receiver, temporary=temporary)
    # Only these literal database names can reach the app's Documents folder.
    # The caller has just installed an absent app and has not launched it.
    for name, source in fixture["files"].items():
        if not control.copy_to(source, f"restore-{name}", f"Documents/{name}"):
            raise FixtureFailure("fixture_copy_to")
    for name, digest in fixture["digests"].items():
        copied = temporary / name
        if not control.copy_from(copied, f"verify-{name}", f"Documents/{name}"):
            raise FixtureFailure("fixture_copy_from")
        copied.chmod(0o600)
        if _sha256(copied) != digest:
            raise FixtureFailure("fixture_roundtrip_digest")
    # Catch any source mutation during device transfers as well as before them.
    after = validate_fixture(staging_path, receiver=receiver, peer=peer)
    if after["manifestSha256"] != fixture["manifestSha256"]:
        raise FixtureFailure("fixture_changed")
    return fixture


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--action", choices=("validate", "restore"), required=True)
    parser.add_argument("--staging-manifest", type=Path, required=True)
    parser.add_argument("--receiver", required=True)
    parser.add_argument("--peer", required=True)
    args = parser.parse_args()
    status = "PASS"
    code = "ok"
    fixture = None
    try:
        if args.action == "validate":
            fixture = validate_fixture(
                args.staging_manifest, receiver=args.receiver, peer=args.peer
            )
        else:
            with tempfile.TemporaryDirectory(prefix="mknoon-ios-identity-restore-") as raw:
                temporary = Path(raw)
                temporary.chmod(0o700)
                fixture = restore_fixture(
                    args.staging_manifest, receiver=args.receiver, peer=args.peer,
                    temporary=temporary,
                )
    except FixtureFailure as error:
        status, code = "FAIL", str(error)
    except BootstrapBlocked:
        status, code = "FAIL", "device_control_unavailable"
    except Exception:
        status, code = "FAIL", "fixture_unavailable"
    result = {
        "schema": RESULT_SCHEMA, "action": args.action, "status": status,
        "containsSecrets": False, "code": code,
    }
    if fixture is not None:
        result.update({key: fixture[key] for key in (
            "manifestSha256", "mlKemPublicKeySha256"
        )})
    print(RESULT_PREFIX + json.dumps(result, sort_keys=True, separators=(",", ":")))
    raise SystemExit(0 if status == "PASS" else 78)


if __name__ == "__main__":
    main()
