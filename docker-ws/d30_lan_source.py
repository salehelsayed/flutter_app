#!/usr/bin/python3
"""SE-42 D30: serve ONE synthetic file to ONE LAN client, capped, then exit.

    host-run ./docker-ws/d30_lan_source.py <synthetic-file> <port> <log-jsonl> [--bind ADDR] [--rate-mbit N]

Caps: 200 MB and 120 s, whichever comes first. One connection only and no
retries. Exits after that connection or 90 s with none. Writes one JSON line per
second of progress plus start/end records, so the caller gets exact windows.
"""
import json
import os
import socket
import subprocess
import sys
import time

CAP_BYTES = 200 * 1024 * 1024
CAP_SECONDS = 120.0
ACCEPT_TIMEOUT = 90.0
CHUNK = 64 * 1024


def lan_address():
    out = subprocess.run(["ipconfig", "getifaddr", "en0"], capture_output=True, text=True)
    return out.stdout.strip()


def serve(path, port, log_path, bind, cap_bytes=CAP_BYTES, cap_seconds=CAP_SECONDS,
          accept_timeout=ACCEPT_TIMEOUT, rate_bits_per_second=None):
    def log(event, **fields):
        with open(log_path, "a") as handle:
            handle.write(json.dumps({"event": event, "utc": time.time(), **fields}) + "\n")

    size = os.path.getsize(path)
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((bind, port))
    server.listen(1)
    server.settimeout(accept_timeout)
    log("listening", bind=bind, port=port, file_bytes=size, cap_bytes=cap_bytes, cap_seconds=cap_seconds,
        rate_bits_per_second=rate_bits_per_second)
    try:
        connection, _ = server.accept()
    except socket.timeout:
        log("no_client")
        server.close()
        return 3
    server.close()
    sent = 0
    started = time.time()
    next_mark = started + 1.0
    reason = "file_end"
    log("start")
    try:
        with open(path, "rb") as source, connection:
            while True:
                if sent >= cap_bytes:
                    reason = "byte_cap"
                    break
                if time.time() - started >= cap_seconds:
                    reason = "time_cap"
                    break
                block = source.read(min(CHUNK, cap_bytes - sent))
                if not block:
                    break
                connection.sendall(block)
                sent += len(block)
                if rate_bits_per_second:
                    time.sleep(max(0.0, started + sent * 8 / rate_bits_per_second - time.time()))
                if time.time() >= next_mark:
                    log("progress", bytes=sent)
                    next_mark += 1.0
    except OSError as error:
        reason = "client_closed:" + type(error).__name__
    log("end", bytes=sent, seconds=round(time.time() - started, 3), reason=reason)
    return 0


def rate_from_argv(argv):
    return int(float(argv[argv.index("--rate-mbit") + 1]) * 1_000_000) if "--rate-mbit" in argv else None


def main(argv):
    if len(argv) < 4:
        print(__doc__, file=sys.stderr)
        return 2
    path, port, log_path = argv[1], int(argv[2]), argv[3]
    bind = argv[argv.index("--bind") + 1] if "--bind" in argv else lan_address()
    if not bind:
        print("no LAN IPv4 on en0", file=sys.stderr)
        return 2
    print("bind=" + bind, flush=True)
    return serve(path, port, log_path, bind, rate_bits_per_second=rate_from_argv(argv))


if __name__ == "__main__":
    sys.exit(main(sys.argv))
