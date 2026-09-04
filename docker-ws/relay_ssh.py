#!/usr/bin/env python3
"""Run a bash script on the production relay box over SSH.

Usage:
    python3 docker-ws/relay_ssh.py < docker-ws/relay_call_registry_probe.sh

The sandbox's OpenSSH client cannot run (uid 501 has no passwd entry), so this
uses paramiko with the repo-local key. No secrets live in this file: the key is
read from ``se.pem`` at the repository root (override with RELAY_SSH_KEY).
"""
import os
import sys

import paramiko

HOST = os.environ.get("RELAY_SSH_HOST", "13.60.15.36")
USER = os.environ.get("RELAY_SSH_USER", "ubuntu")
KEY = os.environ.get(
    "RELAY_SSH_KEY",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "se.pem"),
)
TIMEOUT_SECONDS = int(os.environ.get("RELAY_SSH_TIMEOUT", "180"))


def main() -> int:
    script = sys.stdin.read()
    if not script.strip():
        sys.stderr.write("relay_ssh.py: empty script on stdin\n")
        return 2
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        HOST,
        username=USER,
        key_filename=KEY,
        timeout=30,
        banner_timeout=30,
        auth_timeout=30,
    )
    try:
        stdin, stdout, stderr = client.exec_command("bash -s", timeout=TIMEOUT_SECONDS)
        stdin.write(script)
        stdin.channel.shutdown_write()
        out = stdout.read().decode("utf-8", errors="replace")
        err = stderr.read().decode("utf-8", errors="replace")
        status = stdout.channel.recv_exit_status()
    finally:
        client.close()
    sys.stdout.write(out)
    if err:
        sys.stderr.write(err)
    return status


if __name__ == "__main__":
    sys.exit(main())
