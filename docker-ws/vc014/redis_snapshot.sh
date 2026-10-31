# Read-only, redacted snapshot of the relay's call-control Redis keys for one recipient device (iPhone 13).
# Run on the Hetzner box: python3 docker-ws/hetzner_ssh.py < docker-ws/vc014/redis_snapshot.sh
# Prints only TYPE, PTTL, field names, numbers, booleans and a short list of non-secret enum strings.
cat > /tmp/vc014_snap.py <<'PY'
import base64, json, os, subprocess, time, hashlib
R = "12D3KooWBwczTWzk5eNziaR6KuMUx6Eq1gGYpq9AfPEyQe9op765"
P = os.environ.get("REDIS_PREFIX_OVERRIDE") or "relay:"
pw = open("/etc/mknoon/redis.pass").read().strip()
def rc(*a):
    return subprocess.run(["redis-cli", "-a", pw, "--no-auth-warning", "--raw", *a], capture_output=True, text=True).stdout
def b64(s): return base64.urlsafe_b64encode(s.encode()).decode().rstrip("=")
def unb64(s):
    try: return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4)).decode()
    except Exception: return "?"
def tag(s): return hashlib.sha256(s.encode()).hexdigest()[:6]
SAFE = {"schema","version","platform","environment","kind","state","status","topicKind","storeStatus","wakeStatus","phase","reason","type"}
def red(v, depth=0):
    if isinstance(v, bool) or isinstance(v, (int, float)) or v is None: return v
    if isinstance(v, dict): return {k: (v[k] if k in SAFE and isinstance(v[k], str) and len(v[k]) < 40 else red(v[k], depth+1)) for k in v}
    if isinstance(v, list): return [red(x, depth+1) for x in v[:20]]
    if isinstance(v, str):
        if v.isdigit(): return int(v)
        return "<str len=%d>" % len(v)
    return "<?>"
def val(s):
    s = s.rstrip("\n")
    try: return red(json.loads(s))
    except Exception: return red(s)
def show(k, label):
    t = rc("TYPE", k).strip(); pt = rc("PTTL", k).strip()
    out = {"key": label, "type": t, "pttl_ms": pt}
    if t == "string": out["value"] = val(rc("GET", k))
    elif t == "hash":
        f = rc("HGETALL", k).split("\n")[:-1]
        d = {}
        for i in range(0, len(f) - 1, 2):
            name = f[i] if (f[i] in SAFE or f[i].endswith("Ms") or f[i] in ("record",)) else "field#" + tag(f[i])
            d[name] = val(f[i + 1])
        out["fields"] = d
    elif t in ("set", "zset", "list"):
        n = rc({"set": "SCARD", "zset": "ZCARD", "list": "LLEN"}[t], k).strip(); out["count"] = n
    print(json.dumps(out, ensure_ascii=False))
print(json.dumps({"server_time_ms": int(time.time() * 1000), "server_time": time.strftime("%H:%M:%S", time.gmtime())}))
r = b64(R)
show(P + "call:v1:endpoint-device:" + r, "endpoint-device(iphone13)")
show(P + "call:v1:endpoint:" + r, "endpoint(iphone13 account)")
show(P + "call:v1:endpoint-tombstone:" + r, "endpoint-tombstone(iphone13)")
show(P + "call:v1:token:" + r + ":ios_voip", "token ios_voip(iphone13)")
show(P + "call:v1:token-generation:" + r + ":ios_voip", "token-generation ios_voip(iphone13)")
show(P + "call:v1:token:" + r + ":standard", "token standard(iphone13)")
show(P + "call:v1:wake-directory:" + r, "wake-directory(iphone13)")
for k in rc("--scan", "--pattern", P + "call:v1:wake:" + r + ":*").split():
    sender = unb64(k.rsplit(":", 1)[-1]); show(k, "wake(iphone13<-sender#%s)" % tag(sender))
for k in rc("--scan", "--pattern", P + "call:v1:mailbox:" + r + ":call:*:meta").split():
    base = k[:-len(":meta")]; h = tag(base.rsplit(":", 1)[-1])
    for suf in ("meta", "ids", "wake-claims", "events", "tombstone"):
        show(base + ":" + suf, "call#%s:%s" % (h, suf))
PY
REDIS_PREFIX_OVERRIDE=$(systemctl show relay-server -p Environment --value | tr ' ' '\n' | sed -n 's/^REDIS_PREFIX=//p') python3 /tmp/vc014_snap.py; rm -f /tmp/vc014_snap.py
echo "=== counters"; curl -s 127.0.0.1:2112/metrics | grep -E 'call_store_v1|apns_voip_push_attempts_total' | grep -v ' 0$'
