#!/usr/bin/env python3
"""Plan 406 — mixed-version interop: an OLD build and a NEW build of the Go
node must keep talking to each other, through an OLD and a NEW relay.

OLD = go-mknoon + go-relay-server from --old-ref (default: the last commit
before plan 406), built with --old-toolchain. NEW = this working tree, built
with --new-toolchain. Every pair OLD->NEW, NEW->OLD, NEW->NEW and OLD->OLD
(the control) runs these rows against each relay:

  quic        direct QUIC dial, twice (session resumption); the accepting
              side must still be alive after both handshakes
  tcp         direct TCP dial
  circuit     dial only through the relay circuit
  direct_msg  1:1 v2 message, A -> B, decrypted by B
  inbox       1:1 v2 message stored on the relay inbox, retrieved by B
  group       GossipSub group message, A -> B and B -> A
  media       relay media upload by A, download by B, bytes equal

Exits non-zero on any failure and prints relay, pair and row. Peers and the
relay run on loopback only. One relay runs at a time (fixed metrics port).
Relays use the memory backend unless --redis-url is given (production shape).
"""

import argparse
import base64
import hashlib
import json
import os
import queue
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import uuid

RELAY_PORT = 24101
RELAY_WS_PORT = 24102
RELAY_WSS_PORT = 24103
ANNOUNCED_PUBLIC_IP = "190.190.190.190"


def log(msg):
    print(msg, flush=True)


def run(cmd, cwd, env_extra):
    env = dict(os.environ)
    env.update(env_extra)
    subprocess.run(cmd, cwd=cwd, env=env, check=True)


def build(src_root, out_dir, toolchain, label):
    os.makedirs(out_dir, exist_ok=True)
    env = {"GOTOOLCHAIN": toolchain, "CGO_ENABLED": "0"}
    log(f"[build] {label}: testpeer + relay with {toolchain}")
    run(["go", "build", "-o", os.path.join(out_dir, "testpeer"), "./cmd/testpeer"],
        os.path.join(src_root, "go-mknoon"), env)
    run(["go", "build", "-o", os.path.join(out_dir, "relay"), "."],
        os.path.join(src_root, "go-relay-server"), env)
    version = subprocess.run(["go", "version", os.path.join(out_dir, "testpeer")],
                             capture_output=True, text=True,
                             env=dict(os.environ, GOTOOLCHAIN=toolchain)).stdout.strip()
    log(f"[build] {label}: {version}")


class Relay:
    def __init__(self, binary, workdir, redis_url=None):
        self.workdir = workdir
        key = subprocess.run([binary, "generate-key"], capture_output=True,
                             text=True, check=True).stdout.strip()
        data_dir = os.path.join(workdir, "relaydata")
        shutil.rmtree(data_dir, ignore_errors=True)
        os.makedirs(data_dir)
        env = dict(os.environ,
                   RELAY_PRIVATE_KEY=key,
                   # A public-looking announced IPv4, like production's
                   # RELAY_SERVER_IP: go-libp2p v0.50 autorelay builds circuit
                   # addresses only from PUBLIC relay addresses (it drops
                   # loopback and, unlike v0.39, DNS). Never dialed: peers reach
                   # the relay on loopback.
                   RELAY_SERVER_IP=ANNOUNCED_PUBLIC_IP,
                   RELAY_SERVER_DNS="localhost",
                   RELAY_TCP_PORT=str(RELAY_PORT),
                   RELAY_QUIC_PORT=str(RELAY_PORT),
                   RELAY_WS_PORT=str(RELAY_WS_PORT),
                   RELAY_WSS_PORT=str(RELAY_WSS_PORT),
                   RELAY_DATA_DIR=data_dir)
        if redis_url:
            # Production shape: redis backend with ack-custody admission on.
            env.update(RELAY_BACKEND="redis", REDIS_URL=redis_url,
                       REDIS_PREFIX=f"g406-interop-{uuid.uuid4().hex[:8]}:",
                       DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED="true")
        self.log_path = os.path.join(workdir, "relay.log")
        self.log_file = open(self.log_path, "w")
        self.proc = subprocess.Popen([binary], env=env, stdout=self.log_file,
                                     stderr=subprocess.STDOUT)
        self.peer_id = None
        deadline = time.time() + 20
        while time.time() < deadline and self.peer_id is None:
            time.sleep(0.2)
            with open(self.log_path) as f:
                for line in f:
                    if "Peer ID: " in line:
                        self.peer_id = line.split("Peer ID: ", 1)[1].strip()
            if self.proc.poll() is not None:
                break
        if self.peer_id is None:
            raise RuntimeError(f"relay did not start, see {self.log_path}")
        self.addr = f"/ip4/127.0.0.1/tcp/{RELAY_PORT}/p2p/{self.peer_id}"

    def alive(self):
        return self.proc.poll() is None

    def stop(self):
        self.proc.terminate()
        try:
            self.proc.wait(10)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        self.log_file.close()


class Peer:
    def __init__(self, binary, name, workdir):
        self.name = name
        self.stderr = open(os.path.join(workdir, f"{name}.stderr.log"), "w")
        self.proc = subprocess.Popen([binary], stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=self.stderr,
                                     text=True, bufsize=1)
        self.lines = queue.Queue()
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.proc.stdout:
            self.lines.put(line)
        self.lines.put(None)

    def cmd(self, name, params=None, timeout=60):
        self.proc.stdin.write(json.dumps({"cmd": name, "params": params or {}}) + "\n")
        self.proc.stdin.flush()
        deadline = time.time() + timeout
        while True:
            remaining = deadline - time.time()
            if remaining <= 0:
                raise RuntimeError(f"{self.name}: {name} timed out")
            try:
                line = self.lines.get(timeout=remaining)
            except queue.Empty:
                raise RuntimeError(f"{self.name}: {name} timed out")
            if line is None:
                raise RuntimeError(f"{self.name}: process exited during {name} "
                                   f"(exit {self.proc.poll()})")
            try:
                msg = json.loads(line)
            except ValueError:
                continue
            if msg.get("cmd") == name:
                return msg

    def ok(self, name, params=None, timeout=60):
        res = self.cmd(name, params, timeout)
        if res.get("ok") is not True:
            raise RuntimeError(f"{self.name}: {name} failed: {res.get('errorMessage') or res}")
        return res

    def alive(self):
        return self.proc.poll() is None

    def stop(self):
        try:
            self.cmd("stop", timeout=15)
        except Exception:
            pass
        try:
            self.proc.stdin.close()
        except Exception:
            pass
        try:
            self.proc.wait(10)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        self.stderr.close()


def loopback(addrs, marker, exclude=()):
    out = []
    for a in addrs:
        if not a.startswith("/ip4/") or marker not in a:
            continue
        if any(x in a for x in exclude):
            continue
        out.append(a.replace("/ip4/0.0.0.0/", "/ip4/127.0.0.1/", 1))
    return out


def start_peer(binary, name, relay, workdir):
    p = Peer(binary, name, workdir)
    ident = p.ok("generate_identity")
    mlkem = p.ok("mlkem_keygen")
    p.ok("start", {"relayAddresses": [relay.addr], "autoRegister": False}, timeout=60)
    p.ok("wait_relay", {"timeoutSec": 30}, timeout=40)
    circuit = p.ok("wait_circuit", {"timeoutSec": 30}, timeout=40)
    status = p.ok("status")
    p.info = {
        "peerId": ident["peerId"],
        "publicKey": ident["publicKey"],
        "mlKemPublicKey": mlkem["publicKey"],
        "listen": status.get("listenAddresses") or [],
        "circuit": circuit.get("circuitAddresses") or [],
    }
    return p


def conns_to(peer, target_id):
    status = peer.ok("status")
    return [c for c in (status.get("connections") or []) if c.get("peerId") == target_id]


def disconnect(a, b):
    a.cmd("disconnect", {"peerId": b.info["peerId"]})
    deadline = time.time() + 5
    while time.time() < deadline and conns_to(a, b.info["peerId"]):
        time.sleep(0.1)


def row_direct(a, b, marker, exclude=()):
    addrs = loopback(b.info["listen"], marker, exclude)
    if not addrs:
        raise RuntimeError(f"B has no loopback {marker} listen address: {b.info['listen']}")
    disconnect(a, b)
    a.ok("dial", {"peerId": b.info["peerId"], "addresses": addrs}, timeout=30)
    conns = conns_to(a, b.info["peerId"])
    if not any(marker in c.get("address", "") and not c.get("isRelay") for c in conns):
        raise RuntimeError(f"no direct {marker} connection: {conns}")


def row_quic(a, b):
    for _ in range(2):
        row_direct(a, b, "/quic-v1")
        if not b.alive():
            raise RuntimeError("accepting peer B died after a QUIC handshake")
    b.ok("status")


# Must run first on a fresh pair: once A knows B's QUIC addresses, libp2p
# prefers QUIC and a TCP-only dial reconnects over QUIC instead.
def row_tcp(a, b):
    row_direct(a, b, "/tcp/", exclude=("/ws", "/quic"))


# Must run first on a fresh pair, before A knows any direct address of B.
def row_circuit(a, b, relay):
    addr = f"{relay.addr}/p2p-circuit"
    a.ok("dial", {"peerId": b.info["peerId"], "addresses": [addr]}, timeout=30)
    conns = conns_to(a, b.info["peerId"])
    if not any("/p2p-circuit" in c.get("address", "") for c in conns):
        raise RuntimeError(f"no connection through the relay circuit: {conns}")


def row_direct_msg(a, b):
    text = f"direct-{uuid.uuid4().hex[:8]}"
    b.ok("clear_messages")
    a.ok("send_v2", {"peerId": b.info["peerId"], "text": text,
                     "recipientMlKemPublicKey": b.info["mlKemPublicKey"]}, timeout=40)
    got = b.ok("wait_message", {"fromPeerId": a.info["peerId"], "timeoutSec": 20}, timeout=30)
    if text not in json.dumps(got):
        raise RuntimeError(f"B did not decrypt the message text: {got}")


def row_inbox(a, b):
    text = f"inbox-{uuid.uuid4().hex[:8]}"
    a.ok("inbox_store_v2", {"peerId": b.info["peerId"], "text": text,
                            "recipientMlKemPublicKey": b.info["mlKemPublicKey"]}, timeout=40)
    deadline = time.time() + 20
    while time.time() < deadline:
        got = b.ok("inbox_retrieve", timeout=30)
        if text in json.dumps(got) or got.get("count", 0) > 0:
            return
        time.sleep(1)
    raise RuntimeError("B retrieved nothing from the relay inbox")


def row_group(a, b):
    group_id = f"g406-{uuid.uuid4().hex[:8]}"
    key = base64.b64encode(os.urandom(32)).decode()
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    config = {
        "name": "interop", "groupType": "chat",
        "members": [
            {"peerId": a.info["peerId"], "role": "admin", "publicKey": a.info["publicKey"],
             "mlKemPublicKey": a.info["mlKemPublicKey"]},
            {"peerId": b.info["peerId"], "role": "writer", "publicKey": b.info["publicKey"],
             "mlKemPublicKey": b.info["mlKemPublicKey"]},
        ],
        "createdBy": a.info["peerId"], "createdAt": now,
    }
    for p in (a, b):
        p.ok("group_join", {"groupId": group_id, "groupKey": key, "keyEpoch": 1,
                            "groupConfig": config}, timeout=30)
    for sender, receiver in ((a, b), (b, a)):
        text = f"group-{uuid.uuid4().hex[:8]}"
        deadline = time.time() + 30
        while True:
            sender.ok("group_publish", {"groupId": group_id, "text": text}, timeout=30)
            got = receiver.cmd("wait_group_message", {"groupId": group_id, "timeoutSec": 5},
                               timeout=15)
            if got.get("ok") and got.get("text") == text:
                break
            if time.time() > deadline:
                raise RuntimeError(f"{receiver.name} never received the group message: {got}")


def row_media(a, b, workdir):
    blob_id = str(uuid.uuid4())
    src = os.path.join(workdir, f"{blob_id}.bin")
    dst = os.path.join(workdir, f"{blob_id}.out")
    with open(src, "wb") as f:
        f.write(os.urandom(256 * 1024))
    a.ok("media_upload", {"id": blob_id, "toPeerId": b.info["peerId"],
                          "mime": "application/octet-stream", "filePath": src}, timeout=60)
    b.ok("media_download", {"id": blob_id, "outputPath": dst}, timeout=60)
    digest = lambda p: hashlib.sha256(open(p, "rb").read()).hexdigest()
    if digest(src) != digest(dst):
        raise RuntimeError("downloaded media bytes differ from the upload")


def start_pair(builds, a_ver, b_ver, relay, pair_dir):
    a = start_peer(os.path.join(builds[a_ver], "testpeer"), "A", relay, pair_dir)
    try:
        b = start_peer(os.path.join(builds[b_ver], "testpeer"), "B", relay, pair_dir)
    except Exception:
        a.stop()
        raise
    return a, b


def run_rows(label, relay, a, b, rows, results):
    for name, fn in rows:
        try:
            fn()
            results.append((relay.version, label, name, True, ""))
            log(f"  PASS {relay.version}-relay {label} {name}")
        except Exception as e:
            results.append((relay.version, label, name, False, str(e)))
            log(f"  FAIL {relay.version}-relay {label} {name}: {e}")
        if not (a.alive() and b.alive()):
            results.append((relay.version, label, "alive", False, "a peer process died"))
            log(f"  FAIL {relay.version}-relay {label}: a peer process died")
            return


def run_pair(builds, a_ver, b_ver, relay, workdir, results):
    label = f"{a_ver}->{b_ver}"
    # Two fresh pairs, because the circuit and TCP rows each need a dialer
    # that knows no direct address of its peer yet.
    groups = (
        ("messaging", lambda a, b, d: [
            ("circuit", lambda: row_circuit(a, b, relay)),
            ("direct_msg", lambda: row_direct_msg(a, b)),
            ("inbox", lambda: row_inbox(a, b)),
            ("group", lambda: row_group(a, b)),
            ("media", lambda: row_media(a, b, d)),
        ]),
        ("transport", lambda a, b, d: [
            ("tcp", lambda: row_tcp(a, b)),
            ("quic", lambda: row_quic(a, b)),
        ]),
    )
    for group, make_rows in groups:
        pair_dir = os.path.join(workdir, f"{relay.version}-relay_{a_ver}-{b_ver}_{group}")
        os.makedirs(pair_dir, exist_ok=True)
        try:
            a, b = start_pair(builds, a_ver, b_ver, relay, pair_dir)
        except Exception as e:
            results.append((relay.version, label, f"{group}_setup", False, str(e)))
            log(f"  FAIL {relay.version}-relay {label} {group}_setup: {e}")
            continue
        try:
            run_rows(label, relay, a, b, make_rows(a, b, pair_dir), results)
        finally:
            a.stop()
            b.stop()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--old-ref", default="df0490fc5",
                    help="git ref of the OLD build (default: last commit before plan 406)")
    ap.add_argument("--old-src", help="already-extracted OLD source root (skips git archive)")
    ap.add_argument("--old-toolchain", default="go1.25.0")
    ap.add_argument("--new-toolchain", default="go1.27.1")
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(
        os.path.dirname(os.path.abspath(__file__)))))
    ap.add_argument("--git-dir-repo", help="repo path to run git archive in (default --repo)")
    ap.add_argument("--workdir")
    ap.add_argument("--redis-url", help="run the relays on redis with ack-custody admission "
                    "on, like production (default: memory backend, admission off)")
    args = ap.parse_args()

    workdir = args.workdir or tempfile.mkdtemp(prefix="go406-interop-")
    os.makedirs(workdir, exist_ok=True)
    log(f"[interop] workdir {workdir}")

    old_src = args.old_src
    if not old_src:
        old_src = os.path.join(workdir, "oldsrc")
        shutil.rmtree(old_src, ignore_errors=True)
        os.makedirs(old_src)
        archive = subprocess.Popen(["git", "-C", args.git_dir_repo or args.repo, "archive",
                                    args.old_ref, "go-mknoon", "go-relay-server"],
                                   stdout=subprocess.PIPE)
        subprocess.run(["tar", "-x", "-C", old_src], stdin=archive.stdout, check=True)
        if archive.wait() != 0:
            sys.exit("git archive failed")

    builds = {"old": os.path.join(workdir, "bin-old"), "new": os.path.join(workdir, "bin-new")}
    build(old_src, builds["old"], args.old_toolchain, "old")
    build(args.repo, builds["new"], args.new_toolchain, "new")

    results = []
    for relay_ver in ("old", "new"):
        relay_dir = os.path.join(workdir, f"relay-{relay_ver}")
        os.makedirs(relay_dir, exist_ok=True)
        relay = Relay(os.path.join(builds[relay_ver], "relay"), relay_dir, args.redis_url)
        relay.version = relay_ver
        log(f"[interop] {relay_ver} relay {relay.peer_id}")
        try:
            for a_ver, b_ver in (("old", "new"), ("new", "old"), ("new", "new"), ("old", "old")):
                run_pair(builds, a_ver, b_ver, relay, workdir, results)
                if not relay.alive():
                    results.append((relay_ver, "-", "relay_alive", False, "relay process died"))
                    break
        finally:
            relay.stop()

    failed = [r for r in results if not r[3]]
    log("")
    log(f"[interop] {len(results) - len(failed)} passed, {len(failed)} failed")
    for relay_ver, label, row, _, err in failed:
        log(f"  FAILED {relay_ver}-relay {label} {row}: {err}")
    with open(os.path.join(workdir, "results.json"), "w") as f:
        json.dump([{"relay": r[0], "pair": r[1], "row": r[2], "ok": r[3], "error": r[4]}
                   for r in results], f, indent=1)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
