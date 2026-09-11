#!/usr/bin/env python3
"""Retain local iOS build inputs and exact products; never upload a build."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import io
import json
import plistlib
import re
import shutil
import subprocess
import tarfile
import tempfile
import time
import uuid
import zipfile
from pathlib import Path


SOURCE_PATHS = (
    "lib", "assets", "ios", "go-mknoon", "third_party", "packages",
    "pubspec.yaml", "pubspec.lock", ".fvmrc", "tool/build",
    "scripts/build_ios_appstore_ipa.sh", "scripts/ios_build_provenance.py",
)

SOURCE_BYTE_SUFFIXES = frozenset((
    ".dart", ".go", ".swift", ".kt", ".java", ".c", ".cc", ".cpp",
    ".h", ".hpp", ".m", ".mm", ".s", ".rs", ".py", ".sh",
))
ASSET_BYTE_SUFFIXES = frozenset((".png", ".jpg", ".jpeg", ".webp", ".svg", ".ttf", ".otf"))
SENSITIVE_SOURCE_PATH = re.compile(
    r"(?:^|/)(?:\.env[^/]*|[^/]*(?:secret|credential|service[_-]?account|signing)[^/]*)(?:/|$)"
    r"|\.(?:pem|key|p12|pfx|keystore|jks|mobileprovision)$", re.IGNORECASE)
SENSITIVE_SOURCE_BYTES = re.compile(
    rb"-----BEGIN(?: [A-Z]+)* PRIVATE KEY-----"
    rb"|\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"
    rb"|\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,})\b"
    rb"|(?i:[\"']?(?:private_key|client_secret|refresh_token|access_token|api_secret|password)"
    rb"[\"']?\s*[:=]\s*[\"'][^\"'\r\n]{16,}[\"'])")


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def command(root: Path, *args: str) -> str:
    return subprocess.check_output(args, cwd=root, text=True).strip()


def source_identity(root: Path, extra_files: dict[str, Path]) -> dict:
    names = command(root, "git", "ls-files", "-z", "--cached", "--others",
                    "--exclude-standard", "--", *SOURCE_PATHS).split("\0")
    hashes = {}
    for name in sorted(set(names) - {""}):
        path = root / name
        if path.is_file():
            hashes[name] = sha256(path)
    for name, path in extra_files.items():
        hashes[name] = sha256(path)
    diff = subprocess.check_output(
        ["git", "diff", "HEAD", "--", *SOURCE_PATHS], cwd=root)
    return {
        "revision": command(root, "git", "rev-parse", "HEAD"),
        "branch": command(root, "git", "branch", "--show-current"),
        "relevantWorkingTreeDirty": bool(command(
            root, "git", "status", "--porcelain", "--untracked-files=all",
            "--", *SOURCE_PATHS)),
        "relevantDiffSha256": hashlib.sha256(diff).hexdigest(),
        "files": hashes,
        "limitation": "Identity hashes alone do not reconstruct source; sourceSnapshots retain eligible local changes. "
                      "Before/after equality does not detect transient changes during compilation.",
    }


def retain_source_changes(root: Path, capture: Path, label: str,
                          identity: dict, extra_files: dict[str, Path]) -> dict:
    """Retain filtered local bytes against HEAD, never follow source symlinks."""
    def names(*args: str) -> set[str]:
        return set(command(root, "git", *args, "--", *SOURCE_PATHS).split("\0")) - {""}

    changed = names("diff", "--name-only", "--no-renames", "-z", "HEAD")
    untracked = names("ls-files", "--others", "--exclude-standard", "-z")
    excluded = {name: "explicit build/configuration input; hash only" for name in extra_files}
    extra_paths = {path.resolve() for path in extra_files.values()}
    tracked_paths, new_files, retained_hashes = [], {}, {}
    for name in sorted(changed | untracked):
        path = root / name
        reason = None
        if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
            reason = "symlink or outside source root"
        elif path.resolve() in extra_paths or name in excluded:
            reason = "explicit build/configuration input; hash only"
        elif SENSITIVE_SOURCE_PATH.search(name):
            reason = "credential/signing-shaped path"
        elif not (path.suffix.lower() in SOURCE_BYTE_SUFFIXES or
                  (name.startswith("assets/") and path.suffix.lower() in ASSET_BYTE_SUFFIXES)):
            reason = "outside narrow source/asset byte allowlist; hash only"
        elif subprocess.run(["git", "check-ignore", "--no-index", "--quiet", "--", name],
                            cwd=root).returncode == 0:
            reason = "ignored input; hash only"
        old = subprocess.run(["git", "ls-tree", "HEAD", "--", name], cwd=root,
                             capture_output=True, check=True).stdout
        if old.startswith(b"120000 "):
            reason = "source was a symlink in HEAD"
        if reason:
            excluded[name] = reason
            continue
        previous = subprocess.run(["git", "show", "HEAD:" + name], cwd=root,
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout
        current = path.read_bytes() if path.is_file() else b""
        if SENSITIVE_SOURCE_BYTES.search(previous) or SENSITIVE_SOURCE_BYTES.search(current):
            excluded[name] = "credential-shaped content; hash only"
            continue
        if path.is_file():
            digest = hashlib.sha256(current).hexdigest()
            if identity["files"].get(name) != digest:
                raise ValueError("Source changed while capturing local bytes")
            retained_hashes[name] = digest
        if name in untracked:
            new_files[name] = (current, path.stat().st_mode & 0o777)
        else:
            tracked_paths.append(name)
    patch = capture / ("source-" + label + ".patch")
    patch.write_bytes(subprocess.check_output([
        "git", "diff", "--binary", "--full-index", "--no-ext-diff", "--no-textconv",
        "--no-renames", "HEAD", "--", *tracked_paths], cwd=root) if tracked_paths else b"")
    patch.chmod(0o600)
    archive = capture / ("source-" + label + "-untracked.tar.gz")
    with tarfile.open(archive, "w:gz") as tar:
        for name, (content, mode) in new_files.items():
            member = tarfile.TarInfo(name)
            member.size, member.mode = len(content), mode
            tar.addfile(member, io.BytesIO(content))
    archive.chmod(0o600)
    if source_identity(root, extra_files) != identity:
        patch.unlink()
        archive.unlink()
        raise ValueError("Source changed while capturing local bytes")
    return {
        "revision": identity["revision"],
        "patch": {"path": patch.name, "sha256": sha256(patch)},
        "untrackedArchive": {"path": archive.name, "sha256": sha256(archive)},
        "trackedChanges": tracked_paths, "untrackedFiles": sorted(new_files),
        "retainedFileHashes": retained_hashes, "excluded": excluded,
        "scope": "Filtered local source changes only; restore HEAD, apply patch, then unpack untracked files. "
                 "Excluded/ignored/configuration inputs remain hash-only. Credential detection is conservative, "
                 "not a guarantee; source archives are private and must not be published. "
                 "This does not detect transient compilation-time changes.",
    }


def arguments_identity(root: Path, arguments: list[str]) -> tuple[list[dict], dict[str, Path]]:
    """Keep flag names and hashes; never retain define values or external paths."""
    result, files = [], {}
    for index, argument in enumerate(arguments):
        flag, _, value = argument.partition("=")
        result.append({"position": index,
                       "flag": flag if re.fullmatch(r"--?[a-zA-Z0-9-]+", flag) else "value",
                       "sha256": hashlib.sha256(argument.encode()).hexdigest()})
        if flag in ("--dart-define-from-file", "--target", "-t", "--export-options-plist"):
            if not value and index + 1 < len(arguments):
                value = arguments[index + 1]
            if value:
                path = (root / value).resolve()
                name = (path.relative_to(root).as_posix() if path.is_relative_to(root)
                        else "external-input-" + str(index))
                files[name] = path
    return result, files


def begin(root: Path, arguments: list[str]) -> Path:
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    capture = root / "build/releases" / (".ios-" + stamp + "-" + uuid.uuid4().hex)
    capture.mkdir(parents=True, exist_ok=False, mode=0o700)
    arguments, extra_files = arguments_identity(root, arguments)
    flutter = json.loads(command(root, "flutter", "--version", "--machine"))
    metadata = {
        "schema": 1, "status": "build_pending", "startedAtNs": time.time_ns(),
        "arguments": arguments, "extraInputFiles": sorted(extra_files),
        "before": source_identity(root, extra_files),
        "toolchain": {
            "flutter": {key: flutter[key] for key in (
                "frameworkVersion", "frameworkRevision", "engineRevision",
                "dartSdkVersion", "devToolsVersion", "channel") if key in flutter},
            "xcode": command(root, "xcodebuild", "-version"),
        },
        "distribution": "not_uploaded_by_this_script",
    }
    metadata["sourceSnapshots"] = {"before": retain_source_changes(
        root, capture, "before", metadata["before"], extra_files)}
    (capture / "provenance.json").write_text(json.dumps(metadata, indent=2) + "\n")
    return capture


def image_uuids(root: Path, path: Path) -> list[dict]:
    output = command(root, "xcrun", "dwarfdump", "--uuid", str(path))
    values = [{"uuid": uid.upper(), "architecture": arch} for uid, arch in
              re.findall(r"UUID: ([0-9A-Fa-f-]+) \(([^)]+)\)", output)]
    if not values:
        raise ValueError("No Mach-O UUID found for " + path.name)
    return values


def tree_hashes(root: Path) -> dict[str, str]:
    return {path.relative_to(root).as_posix(): sha256(path)
            for path in sorted(root.rglob("*")) if path.is_file()}


def retain(root: Path, capture: Path, archive: Path, ipa: Path,
           arguments: list[str] | None = None) -> Path:
    metadata = json.loads((capture / "provenance.json").read_text())
    if metadata["status"] != "build_pending":
        raise ValueError("Capture already completed; refusing overwrite")
    if arguments is None:
        extra_files = {name: root / name for name in metadata["extraInputFiles"]}
    else:
        argument_metadata, extra_files = arguments_identity(root, arguments)
        if argument_metadata != metadata["arguments"]:
            raise ValueError("Build arguments differ from the recorded inputs")
    metadata["after"] = source_identity(root, extra_files)
    snapshots = metadata.setdefault("sourceSnapshots", {})
    if "before" not in snapshots:
        metadata["sourceBeforeBytesUnavailable"] = "Capture began without source-byte retention."
    if metadata["after"] != metadata["before"] or "before" not in snapshots:
        snapshots["after"] = retain_source_changes(
            root, capture, "after", metadata["after"], extra_files)
    if (archive / "Info.plist").stat().st_mtime_ns < metadata["startedAtNs"]:
        raise ValueError("Archive predates this build; refusing stale products")
    if ipa.stat().st_mtime_ns < metadata["startedAtNs"]:
        raise ValueError("IPA predates this build; refusing stale products")
    app = archive / "Products/Applications/Runner.app"
    info = plistlib.loads((app / "Info.plist").read_bytes())
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    if not all(re.fullmatch(r"[A-Za-z0-9._-]+", item) for item in (version, build)):
        raise ValueError("Unsafe version/build identity")
    copied_archive, copied_ipa = capture / "Runner.xcarchive", capture / "mknoon.ipa"
    before_archive = tree_hashes(archive)
    before_ipa = sha256(ipa)
    shutil.copytree(archive, copied_archive)
    shutil.copy2(ipa, copied_ipa)
    if tree_hashes(copied_archive) != before_archive or sha256(copied_ipa) != before_ipa:
        raise ValueError("Products changed while being retained")
    metadata["bundle"] = {key: info.get(key) for key in (
        "CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion",
        "DTXcodeBuild", "DTSDKName", "MinimumOSVersion")}
    archive_info = plistlib.loads((copied_archive / "Info.plist").read_bytes())
    metadata["archiveCreationDate"] = str(archive_info.get("CreationDate", "unknown"))
    metadata["archiveFilesSha256"] = before_archive
    metadata["ipaSha256"] = before_ipa
    metadata["ipaFilesSha256"] = {}
    metadata["images"] = {}
    with zipfile.ZipFile(copied_ipa) as zipped, tempfile.TemporaryDirectory() as temporary:
        ipa_info = plistlib.loads(zipped.read("Payload/Runner.app/Info.plist"))
        for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"):
            if ipa_info[key] != info[key]:
                raise ValueError("IPA/archive bundle identity mismatch")
        for name in zipped.namelist():
            if not name.endswith("/"):
                metadata["ipaFilesSha256"][name] = hashlib.sha256(zipped.read(name)).hexdigest()
        copied_app = copied_archive / "Products/Applications/Runner.app"
        for relative in ("Runner", "Frameworks/App.framework/App", "Frameworks/Flutter.framework/Flutter"):
            binary = copied_app / relative
            archive_ids = image_uuids(root, binary)
            extracted = Path(temporary) / Path(relative).name
            extracted.write_bytes(zipped.read("Payload/Runner.app/" + relative))
            if image_uuids(root, extracted) != archive_ids:
                raise ValueError("IPA/archive UUID mismatch for " + relative)
            metadata["images"]["Products/Applications/Runner.app/" + relative] = archive_ids
    for dwarf in sorted((copied_archive / "dSYMs").glob("*/Contents/Resources/DWARF/*")):
        if dwarf.is_file():
            metadata["images"][dwarf.relative_to(copied_archive).as_posix()] = image_uuids(root, dwarf)
    for binary, dsym in (
        ("Runner", "Runner.app.dSYM/Contents/Resources/DWARF/Runner"),
        ("Frameworks/App.framework/App", "App.framework.dSYM/Contents/Resources/DWARF/App"),
        ("Frameworks/Flutter.framework/Flutter", "Flutter.framework.dSYM/Contents/Resources/DWARF/Flutter"),
    ):
        if metadata["images"].get("dSYMs/" + dsym) != metadata["images"]["Products/Applications/Runner.app/" + binary]:
            raise ValueError("Missing or mismatched dSYM for " + binary)
    metadata["sourceUnchanged"] = metadata["before"] == metadata["after"]
    metadata["status"] = "retained" if metadata["sourceUnchanged"] else "retained_source_changed"
    (capture / "provenance.json").write_text(json.dumps(metadata, indent=2) + "\n")
    destination = root / "build/releases" / (version + "+" + build) / capture.name.lstrip(".")
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        raise FileExistsError("Retained destination already exists")
    capture.rename(destination)
    return destination


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("begin", "retain"))
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--capture", type=Path)
    options, arguments = parser.parse_known_args()
    root = options.root.resolve()
    if options.action == "begin":
        result = begin(root, arguments[1:] if arguments[:1] == ["--"] else arguments)
    else:
        if options.capture is None:
            parser.error("retain requires --capture")
        ipas = list((root / "build/ios/ipa").glob("*.ipa"))
        if len(ipas) != 1:
            parser.error("expected exactly one exported IPA")
        result = retain(root, options.capture.resolve(), root / "build/ios/archive/Runner.xcarchive", ipas[0],
                        arguments[1:] if arguments[:1] == ["--"] else arguments)
    print(result.relative_to(root))


if __name__ == "__main__":
    main()
