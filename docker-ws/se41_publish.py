#!/usr/bin/env python3
"""Publish one owner-signed SE-41 version file to updates.mknoon.xyz (owner-approved runs only).

Usage: python3 docker-ws/se41_publish.py <signed file> <backup suffix, e.g. seq3>

Backs up the live file as version.json.<suffix>.bak (refuses to overwrite an existing backup),
uploads to version.json.tmp, checks the remote sha256 equals the local one, then moves it into place
with an atomic mv. Uses the relay's se.pem as ec2-user (paramiko RSA key). Prints hashes only.
"""
import hashlib
import os
import sys

import paramiko

HERE = os.path.dirname(os.path.abspath(__file__))
KEY = os.path.join(HERE, "..", "se.pem")
HOST = "updates.mknoon.xyz"
D = "/srv/updates/mknoon"


def run(c, cmd):
    _, out, err = c.exec_command(cmd, timeout=60)
    rc = out.channel.recv_exit_status()
    return rc, out.read().decode().strip(), err.read().decode().strip()


def main() -> int:
    local, suffix = sys.argv[1], sys.argv[2]
    want = hashlib.sha256(open(local, "rb").read()).hexdigest()
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, username="ec2-user", pkey=paramiko.RSAKey.from_private_key_file(KEY),
              timeout=30, look_for_keys=False, allow_agent=False)
    try:
        bak = f"{D}/version.json.{suffix}.bak"
        rc, out, _ = run(c, f"test -e {bak} && echo exists || echo free")
        if out != "free":
            print(f"refused: backup {bak} already exists")
            return 3
        rc, out, err = run(c, f"cp -p {D}/version.json {bak} && sha256sum {bak}")
        if rc != 0:
            print("backup failed:", err)
            return 4
        print("backup", out.split()[0][:16], bak)
        sftp = c.open_sftp()
        sftp.put(local, f"{D}/version.json.tmp")
        sftp.close()
        rc, out, _ = run(c, f"sha256sum {D}/version.json.tmp")
        if out.split()[0] != want:
            print("refused: uploaded sha mismatch")
            run(c, f"rm -f {D}/version.json.tmp")
            return 5
        rc, out, err = run(c, f"mv {D}/version.json.tmp {D}/version.json && sha256sum {D}/version.json")
        print("live", out.split()[0] if rc == 0 else err, "want", want)
        return 0 if rc == 0 and out.split()[0] == want else 6
    finally:
        c.close()


if __name__ == "__main__":
    sys.exit(main())
