#!/usr/bin/env python3
"""Run a bash script on the Hetzner test relay box over SSH.

Usage:
    python3 docker-ws/hetzner_ssh.py < script.sh
    python3 docker-ws/hetzner_ssh.py --put <local> <remote> [mode]

Uses paramiko (the sandbox's OpenSSH client cannot run for uid 501). Auth:
the key at HETZNER_SSH_KEY if it exists, else the password from
HETZNER_SSH_PASS in the repository's .env. No secrets live in this file.
"""
import os
import sys

import paramiko

HERE = os.path.dirname(os.path.abspath(__file__))
HOST = os.environ.get("HETZNER_SSH_HOST", "2.29.62.121")
USER = os.environ.get("HETZNER_SSH_USER", "root")
KEY = os.environ.get("HETZNER_SSH_KEY", os.path.expanduser("~/.ssh/hetzner_relay_ed25519"))
TIMEOUT_SECONDS = int(os.environ.get("HETZNER_SSH_TIMEOUT", "900"))


def env_password():
    path = os.path.join(HERE, "..", ".env")
    try:
        with open(path) as f:
            for line in f:
                if line.startswith("HETZNER_SSH_PASS="):
                    return line.split("=", 1)[1].strip().strip('"').strip("'")
    except OSError:
        pass
    return None


def connect():
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    kwargs = dict(username=USER, timeout=30, banner_timeout=30, auth_timeout=30)
    if os.path.exists(KEY):
        kwargs["key_filename"] = KEY
        kwargs["look_for_keys"] = False
    else:
        password = env_password()
        if not password:
            sys.exit("hetzner_ssh.py: no key and no HETZNER_SSH_PASS in .env")
        kwargs["password"] = password
        kwargs["look_for_keys"] = False
        kwargs["allow_agent"] = False
    client.connect(HOST, **kwargs)
    return client


def main() -> int:
    client = connect()
    try:
        if len(sys.argv) >= 4 and sys.argv[1] == "--put":
            sftp = client.open_sftp()
            sftp.put(sys.argv[2], sys.argv[3])
            if len(sys.argv) >= 5:
                sftp.chmod(sys.argv[3], int(sys.argv[4], 8))
            sftp.close()
            print(f"put {sys.argv[2]} -> {sys.argv[3]}")
            return 0
        script = sys.stdin.read()
        if not script.strip():
            sys.stderr.write("hetzner_ssh.py: empty script on stdin\n")
            return 2
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
