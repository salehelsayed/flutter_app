#!/usr/bin/env python3
"""Upload one file to the production relay box over SFTP.

Usage:
    python3 docker-ws/relay_sftp_put.py <local-path> <remote-path>

Same connection parameters as relay_ssh.py (paramiko, repo-local ``se.pem``;
override with RELAY_SSH_HOST / RELAY_SSH_USER / RELAY_SSH_KEY). Prints the
remote size so the caller can verify the transfer before installing.
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


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: relay_sftp_put.py <local-path> <remote-path>\n")
        return 2
    local, remote = sys.argv[1], sys.argv[2]
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(HOST, username=USER, key_filename=KEY, timeout=30,
                   banner_timeout=30, auth_timeout=30)
    try:
        sftp = client.open_sftp()
        try:
            sftp.put(local, remote)
            print(f"uploaded {local} -> {remote} size={sftp.stat(remote).st_size}")
        finally:
            sftp.close()
    finally:
        client.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
