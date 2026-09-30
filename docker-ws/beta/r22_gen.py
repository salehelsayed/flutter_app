#!/usr/bin/env python3
"""R2-2 load generator: fake `_mknoon._tcp` services, registered on this Mac only (lo0 and/or LocalOnly).

LocalOnly (interface index -1) records are never sent on the network. Only clients of this Mac's
mDNSResponder see them, which includes the iPhone simulator. Three groups:
  quiet  - registered once, never change (the app re-resolves them every ~20 s)
  update - TXT key `seq` changes every 0.3-1.5 s (each change is lost+found in the app, so a new
           resolve, and it also sends a fresh reply to any resolve that is still open)
  churn  - registered for 1-4 s, removed for 0.2-1 s, repeat
Stops at the deadline or when <out>/.stop exists. Writes <out>/services.txt and <out>/gen_counts.txt.
Usage: r22_gen.py <out dir> <seconds> <quiet> <update> <churn> [port base, default 47000]
"""
import ctypes, os, random, select, socket, sys, time

OUT, DUR = sys.argv[1], float(sys.argv[2])
NQ, NU, NC = int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
PORT0 = int(sys.argv[6]) if len(sys.argv) > 6 else 47000
# Interfaces (R22_IF, comma list, default lo0): "lo0" = loopback, "local" = LocalOnly (-1). Both never
# leave this Mac. The simulator's NWBrowser does not report LocalOnly records, but its resolves do get
# answers from them, so "lo0,local" gives every lookup two replies (like a service on two interfaces).
IFACES = [0xFFFFFFFF if n == "local" else socket.if_nametoindex(n) for n in os.environ.get("R22_IF", "lo0").split(",")]
PREFIX = os.environ.get("R22_PREFIX", "mknoon-stress")
TYPE = b"_mknoon._tcp"

lib = ctypes.CDLL("/usr/lib/system/libsystem_dnssd.dylib")
REPLY = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_int32,
                         ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p)
lib.DNSServiceRegister.argtypes = [ctypes.POINTER(ctypes.c_void_p), ctypes.c_uint32, ctypes.c_uint32,
                                   ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p,
                                   ctypes.c_uint16, ctypes.c_uint16, ctypes.c_char_p, REPLY, ctypes.c_void_p]
lib.DNSServiceRegister.restype = ctypes.c_int32
lib.DNSServiceUpdateRecord.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32,
                                       ctypes.c_uint16, ctypes.c_char_p, ctypes.c_uint32]
lib.DNSServiceUpdateRecord.restype = ctypes.c_int32
lib.DNSServiceRefSockFD.argtypes = [ctypes.c_void_p]
lib.DNSServiceRefSockFD.restype = ctypes.c_int
lib.DNSServiceProcessResult.argtypes = [ctypes.c_void_p]
lib.DNSServiceProcessResult.restype = ctypes.c_int32
lib.DNSServiceRefDeallocate.argtypes = [ctypes.c_void_p]
lib.DNSServiceRefDeallocate.restype = None

counts = {"register": 0, "remove": 0, "update": 0, "registered_ok": 0, "errors": 0}
last_errors = []


@REPLY
def on_reg(ref, flags, err, name, regtype, domain, ctx):
    if err != 0:
        counts["errors"] += 1
        last_errors.append(err)
    else:
        counts["registered_ok"] += 1


B58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"


def peer_id():
    # A well-formed libp2p Ed25519 peer id: identity multihash of the protobuf public key.
    key = bytes([0x08, 0x01, 0x12, 0x20]) + os.urandom(32)
    n = int.from_bytes(bytes([0x00, len(key)]) + key, "big")
    s = ""
    while n:
        n, r = divmod(n, 58)
        s = B58[r] + s
    return "1" + s  # one leading zero byte


def txt(d):
    out = b""
    for k, v in d.items():
        e = ("%s=%s" % (k, v)).encode()
        out += bytes([len(e)]) + e
    return out


class Svc:
    def __init__(self, i, kind):
        self.kind = kind
        self.name = ("%s-%s%d" % (PREFIX, kind[0], i)).encode()
        self.port = PORT0 + i
        self.pid = peer_id()
        self.seq = 0
        self.refs = []
        self.next = float("inf")

    def attrs(self):
        d = {"peerId": self.pid, "quicPort": self.port, "tcpPort": self.port}
        if self.kind == "update":
            d["seq"] = self.seq
        return d

    def up(self):
        t = txt(self.attrs())
        for ifindex in IFACES:
            ref = ctypes.c_void_p()
            err = lib.DNSServiceRegister(ctypes.byref(ref), 0, ifindex, self.name, TYPE, b"local.", None,
                                         socket.htons(self.port), len(t), t, on_reg, None)
            if err:
                counts["errors"] += 1
                last_errors.append(err)
                continue
            self.refs.append(ref)
        counts["register"] += 1

    def down(self):
        if self.refs:
            for ref in self.refs:
                lib.DNSServiceRefDeallocate(ref)
            self.refs = []
            counts["remove"] += 1

    def update(self):
        self.seq += 1
        t = txt(self.attrs())
        for ref in self.refs:
            err = lib.DNSServiceUpdateRecord(ref, None, 0, len(t), t, 0)
            if err:
                counts["errors"] += 1
                last_errors.append(err)
        counts["update"] += 1


svcs = [Svc(i, "quiet") for i in range(NQ)]
svcs += [Svc(NQ + i, "update") for i in range(NU)]
svcs += [Svc(NQ + NU + i, "churn") for i in range(NC)]
with open(os.path.join(OUT, "services.txt"), "w") as f:
    for s in svcs:
        f.write("%d %s %s\n" % (s.port, s.kind, s.name.decode()))

stop = os.path.join(OUT, ".stop")
t0 = time.time()
end = t0 + DUR
now = t0
for s in svcs:
    s.up()
    if s.kind == "update":
        s.next = now + random.uniform(0.3, 1.5)
    elif s.kind == "churn":
        s.next = now + random.uniform(1.0, 4.0)
next_report = now + 10


def report():
    with open(os.path.join(OUT, "gen_counts.txt"), "a") as f:
        f.write("t=%ds %s last_errors=%s\n" % (time.time() - t0, " ".join("%s=%d" % kv for kv in counts.items()),
                                             last_errors[-3:]))


try:
    while now < end and not os.path.exists(stop):
        fds = {}
        for s in svcs:
            for ref in s.refs:
                fds[lib.DNSServiceRefSockFD(ref)] = ref
        ready = select.select(list(fds), [], [], 0.05)[0] if fds else []
        for fd in ready:
            lib.DNSServiceProcessResult(fds[fd])
        now = time.time()
        for s in svcs:
            if now < s.next:
                continue
            if s.kind == "update" and s.refs:
                s.update()
                s.next = now + random.uniform(0.3, 1.5)
            elif s.kind == "churn":
                if s.refs:
                    s.down()
                    s.next = now + random.uniform(0.2, 1.0)
                else:
                    s.up()
                    s.next = now + random.uniform(1.0, 4.0)
        if now >= next_report:
            report()
            next_report = now + 10
finally:
    for s in svcs:
        s.down()
    report()
    print("generator done after %ds" % (time.time() - t0))
