#!/bin/bash
# Codex CLI "unauthorized" diagnostic. Run it in a normal Mac Terminal:
#   bash /Volumes/CrucialX9/flutter_app/docker-ws/codex_auth_diag3.sh
# It prints no secret values. It writes a copy of its output next to itself.
OUT="$(cd "$(dirname "$0")" && pwd)/codex_auth_diag3_result.txt"
redact() {
  sed -E -e 's/((KEY|TOKEN|SECRET|PASS)[A-Za-z_]*[[:space:]]*=[[:space:]]*).*/\1<redacted>/I' \
         -e 's/(sk-[A-Za-z0-9_-]{4})[A-Za-z0-9_-]+/\1<redacted>/g' \
         -e 's/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/<jwt>/g' \
         -e 's/(Bearer )[A-Za-z0-9._-]+/\1<redacted>/g'
}
auth_shape() {
  python3 - "$1" <<'PY'
import json, sys, base64, time, os
p = sys.argv[1]
try:
    st = os.stat(p)
    print("  file:", p, "mtime:", time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(st.st_mtime)))
    d = json.load(open(p))
except Exception as e:
    print("  cannot read:", p, e); sys.exit(0)
def jwt(t):
    seg = t.split('.')[1]; seg += '=' * (-len(seg) % 4)
    return json.loads(base64.urlsafe_b64decode(seg))
print("  auth_mode:", d.get("auth_mode"), "| OPENAI_API_KEY in file:", "set" if d.get("OPENAI_API_KEY") else "none",
      "| last_refresh:", d.get("last_refresh"))
t = (d.get("tokens") or {}).get("access_token")
if t:
    c = jwt(t); exp = c.get("exp")
    print("  access_token exp:", time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(exp)), "expired:", exp < time.time())
PY
}
run_codex() {
  label="$1"; shift
  echo "--- codex exec test: $label ---"
  d=$(mktemp -d)
  ( cd "$d" && "$@" perl -e 'alarm 180; exec @ARGV' codex exec --skip-git-repo-check -s read-only \
      -c model_reasoning_effort=low "Reply with exactly the word OK and nothing else." </dev/null ) 2>&1 \
    | redact | tail -25
  echo "exit=${PIPESTATUS[0]}"
  rm -rf "$d"
}
main() {
  date
  echo "=== env in this Terminal ==="
  echo "CODEX_HOME=${CODEX_HOME:-<unset>}"
  if [ -n "$OPENAI_API_KEY" ]; then echo "OPENAI_API_KEY=<set, len ${#OPENAI_API_KEY}, prefix ${OPENAI_API_KEY:0:8}>"; else echo "OPENAI_API_KEY=<unset>"; fi
  [ -n "$CODEX_API_KEY" ] && echo "CODEX_API_KEY=<set>"
  env | grep -E '^(OPENAI|CODEX)[A-Z_]*=' | sed -E 's/=.*/=<set>/'
  which -a codex; codex --version
  echo "=== codex lines in shell profiles ==="
  for f in "$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.zprofile"; do
    [ -f "$f" ] && grep -nE 'codex|CODEX|OPENAI' "$f" | redact | sed "s|^|$(basename "$f"):|"
  done
  echo "=== .zshrc 110-126 ==="; sed -n '110,126p' "$HOME/.zshrc" | redact
  echo "=== auth.json files ==="
  auth_shape "$HOME/.codex/auth.json"
  [ -n "$CODEX_HOME" ] && [ "$CODEX_HOME" != "$HOME/.codex" ] && auth_shape "$CODEX_HOME/auth.json"
  echo "=== OPENAI_API_KEY check (HTTP status only) ==="
  if [ -n "$OPENAI_API_KEY" ]; then
    curl -s -m 20 -o /dev/null -w 'GET /v1/models with env key -> HTTP %{http_code}\n' \
      https://api.openai.com/v1/models -H "Authorization: Bearer $OPENAI_API_KEY"
  fi
  echo "=== codex login status ==="
  codex login status 2>&1 | redact
  env -u OPENAI_API_KEY -u CODEX_API_KEY codex login status 2>&1 | redact | sed 's/^/(without env key) /'
  run_codex "A: this Terminal's env" env
  run_codex "B: without OPENAI_API_KEY/CODEX_API_KEY" env -u OPENAI_API_KEY -u CODEX_API_KEY
  [ -n "$CODEX_HOME" ] && run_codex "C: without CODEX_HOME and env keys" env -u CODEX_HOME -u OPENAI_API_KEY -u CODEX_API_KEY
  echo "=== recent 401/unauthorized lines in codex logs ==="
  python3 - "${CODEX_HOME:-$HOME/.codex}/logs_2.sqlite" <<'PY' | redact
import sqlite3, sys, re
try:
    db = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
except Exception as e:
    print("cannot open:", e); sys.exit(0)
pat = re.compile(r'unauthori|\b401\b|refresh_token|token_expired|invalid_api_key|log ?in again', re.I)
for (t,) in db.execute("select name from sqlite_master where type='table'"):
    try:
        rows = db.execute(f'select * from "{t}" order by rowid desc limit 30000').fetchall()
    except Exception:
        continue
    hits = [r for r in rows if any(isinstance(v, str) and pat.search(v) for v in r)]
    print(f"table {t}: {len(hits)} matching rows in last {len(rows)}")
    for r in hits[:12]:
        print("  ", " | ".join(str(v)[:220] for v in r if v is not None)[:500])
PY
  echo "=== done ==="
}
main 2>&1 | tee "$OUT"
echo "Saved to $OUT"
