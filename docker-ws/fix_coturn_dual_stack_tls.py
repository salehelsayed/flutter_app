#!/usr/bin/env python3
"""Preview/apply the production TURN listener repair on the relay host.

Run with sudo on the relay. Default is a non-mutating preview. --apply backs up
the config, copies the existing certificate with restricted permissions, and
restarts coturn only when its allocation port range is unused. No secret value
is printed. AWS ingress and advertised credential URLs are separate steps.
"""

import argparse
import datetime
import grp
import ipaddress
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile


def render_config(original, private_ipv4, public_ipv4, public_ipv6):
    for address, version in [(private_ipv4, 4), (public_ipv4, 4), (public_ipv6, 6)]:
        if ipaddress.ip_address(address).version != version:
            raise ValueError("Wrong address family")
    replacements = {
        "listening-ip": [private_ipv4, public_ipv6, "127.0.0.1", "::1"],
        "relay-ip": [private_ipv4, public_ipv6],
        "external-ip": [f"{public_ipv4}/{private_ipv4}"],
        "tls-listening-port": ["5349"],
        "cert": ["/etc/coturn/tls/fullchain.pem"],
        "pkey": ["/etc/coturn/tls/privkey.pem"],
        "no-tlsv1": [None],
        "no-tlsv1_1": [None],
    }
    retained = []
    for line in original.splitlines():
        stripped = line.strip()
        key = stripped.split("=", 1)[0]
        if not stripped.startswith("#") and (key in replacements or key == "no-tls"):
            continue
        if stripped == "# Managed dual-stack TURN listeners and TLS certificate:":
            continue
        retained.append(line)
    while retained and not retained[-1].strip():
        retained.pop()
    retained += ["", "# Managed dual-stack TURN listeners and TLS certificate:"]
    for key, values in replacements.items():
        retained += [key if value is None else f"{key}={value}" for value in values]
    return "\n".join(retained) + "\n"


def active_allocation_count(pid, first_port, last_port):
    inodes = set()
    for fd in (Path("/proc") / str(pid) / "fd").iterdir():
        try:
            target = os.readlink(fd)
        except FileNotFoundError:
            continue
        if target.startswith("socket:["):
            inodes.add(target[8:-1])
    count = 0
    for name in ["udp", "udp6", "tcp", "tcp6"]:
        for line in (Path("/proc/net") / name).read_text().splitlines()[1:]:
            fields = line.split()
            port = int(fields[1].rsplit(":", 1)[1], 16)
            if first_port <= port <= last_port and fields[9] in inodes:
                count += 1
    return count


def atomic_write(path, content, mode, uid, gid):
    fd, temporary = tempfile.mkstemp(prefix=".turn-repair-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as target:
            target.write(content)
        os.chmod(temporary, mode)
        os.chown(temporary, uid, gid)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--private-ipv4", required=True)
    parser.add_argument("--public-ipv4", required=True)
    parser.add_argument("--public-ipv6", required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    config = Path("/etc/turnserver.conf")
    original = config.read_text()
    rendered = render_config(original, args.private_ipv4, args.public_ipv4, args.public_ipv6)
    cert_source = Path("/etc/letsencrypt/live/mknoun.xyz")
    subprocess.run(["openssl", "x509", "-in", str(cert_source / "fullchain.pem"),
                    "-checkend", "604800", "-noout"], check=True, capture_output=True)
    cert_public = subprocess.check_output(["openssl", "x509", "-in", str(cert_source / "fullchain.pem"), "-pubkey", "-noout"])
    key_public = subprocess.check_output(["openssl", "pkey", "-in", str(cert_source / "privkey.pem"), "-pubout"], stderr=subprocess.DEVNULL)
    if cert_public != key_public:
        raise RuntimeError("Certificate/key mismatch")
    pid = int(subprocess.check_output(["systemctl", "show", "coturn", "-p", "MainPID", "--value"]))
    configured = dict(line.split("=", 1) for line in original.splitlines()
                      if "=" in line and not line.lstrip().startswith("#"))
    allocation_count = active_allocation_count(pid, int(configured.get("min-port", 49152)),
                                               int(configured.get("max-port", 65535)))
    print(json.dumps({"mode": "apply" if args.apply else "preview", "config_changed": original != rendered,
                      "active_allocation_sockets": allocation_count, "certificate_key_match": True,
                      "listeners": [args.private_ipv4, args.public_ipv6, "127.0.0.1", "::1"],
                      "tls_port": 5349}), flush=True)
    if not args.apply:
        return
    if allocation_count:
        raise RuntimeError("Active TURN allocations: wait for calls to drain before applying")
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup = Path("/var/backups/mknoon-turn") / stamp
    backup.mkdir(parents=True, mode=0o700)
    os.chmod(backup.parent, 0o700)
    shutil.copy2(config, backup / "turnserver.conf")
    tls = Path("/etc/coturn/tls")
    tls.mkdir(parents=True, exist_ok=True, mode=0o750)
    group = grp.getgrnam("turnserver").gr_gid
    os.chmod(tls, 0o750)
    os.chown(tls, 0, group)
    for name in ["fullchain.pem", "privkey.pem"]:
        destination = tls / name
        if destination.exists():
            shutil.copy2(destination, backup / name)
        atomic_write(destination, (cert_source / name).read_text(), 0o640, 0, group)
    hook = Path("/etc/letsencrypt/renewal-hooks/deploy/50-mknoon-coturn")
    if hook.exists():
        shutil.copy2(hook, backup / "50-mknoon-coturn")
    hook_text = """#!/bin/sh
set -eu
[ "${RENEWED_LINEAGE:-}" = /etc/letsencrypt/live/mknoun.xyz ] || exit 0
install -o root -g turnserver -m 0640 "$RENEWED_LINEAGE/fullchain.pem" /etc/coturn/tls/fullchain.pem
install -o root -g turnserver -m 0640 "$RENEWED_LINEAGE/privkey.pem" /etc/coturn/tls/privkey.pem
# coturn 4.6.1 reload_ssl_certs handles SIGUSR2 without terminating calls.
systemctl kill --kill-who=main --signal=SIGUSR2 coturn.service
"""
    atomic_write(hook, hook_text, 0o750, 0, 0)
    st = config.stat()
    atomic_write(config, rendered, stat.S_IMODE(st.st_mode), st.st_uid, st.st_gid)
    try:
        subprocess.run(["systemctl", "restart", "coturn"], check=True)
        subprocess.run(["systemctl", "is-active", "--quiet", "coturn"], check=True)
    except subprocess.CalledProcessError:
        shutil.copy2(backup / "turnserver.conf", config)
        subprocess.run(["systemctl", "restart", "coturn"], check=False)
        raise
    print(json.dumps({"applied": True, "backup": str(backup),
                      "certificate_renewal": "SIGUSR2 reload; no call-interrupting restart"}), flush=True)


if __name__ == "__main__":
    main()
