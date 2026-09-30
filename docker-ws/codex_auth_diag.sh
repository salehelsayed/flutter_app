#!/bin/bash
# Read-only Codex CLI auth diagnostic. Prints no secret values.
echo "=== whoami / HOME ==="; whoami; echo "$HOME"
echo "=== codex binaries ==="
for p in $(which -a codex 2>/dev/null) /opt/homebrew/bin/codex /usr/local/bin/codex "$HOME/.npm-global/bin/codex"; do
  [ -e "$p" ] && ls -la "$p"
done
CODEX=$(which codex 2>/dev/null || ls /opt/homebrew/bin/codex /usr/local/bin/codex 2>/dev/null | head -1)
echo "CODEX=$CODEX"
echo "=== version ==="; "$CODEX" --version 2>&1 | head -3
echo "=== npm/brew install info ==="
npm ls -g --depth=0 2>/dev/null | grep -i codex
brew list --versions codex 2>/dev/null
echo "=== CODEX_HOME / env names ==="
env | grep -iE '^(CODEX|OPENAI)[A-Z_]*=' | sed -E 's/=.*/=<set>/'
CH="${CODEX_HOME:-$HOME/.codex}"
echo "CODEX_HOME resolved: $CH"
echo "=== codex home listing ==="; ls -la "$CH" 2>&1 | head -40
echo "=== config.toml (secret-looking values redacted) ==="
sed -E 's/((key|token|secret|bearer)[A-Za-z_]*[[:space:]]*=[[:space:]]*).*/\1<redacted>/I' "$CH/config.toml" 2>&1 | head -80
echo "=== auth.json shape ==="
python3 - "$CH/auth.json" <<'PY'
import json, sys, base64, time, os
p = sys.argv[1]
try:
    st = os.stat(p)
    print("mtime:", time.strftime('%Y-%m-%d %H:%M:%S %Z', time.localtime(st.st_mtime)), "mode:", oct(st.st_mode & 0o777))
    d = json.load(open(p))
except Exception as e:
    print("cannot read auth.json:", e); sys.exit(0)
def jwt(t):
    try:
        seg = t.split('.')[1]; seg += '=' * (-len(seg) % 4)
        return json.loads(base64.urlsafe_b64decode(seg))
    except Exception as e:
        return {"_decode_error": str(e)}
now = time.time()
for k, v in d.items():
    if k == "tokens" and isinstance(v, dict):
        for tk, tv in v.items():
            if isinstance(tv, str) and tv.count('.') == 2:
                c = jwt(tv)
                exp = c.get('exp')
                auth = c.get('https://api.openai.com/auth', {})
                print(f"tokens.{tk}: JWT exp={time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(exp)) if exp else None} "
                      f"expired={exp < now if exp else None} plan={auth.get('chatgpt_plan_type')} "
                      f"sub_until={auth.get('chatgpt_subscription_active_until')}")
            else:
                print(f"tokens.{tk}: {'<set, len %d>' % len(tv) if isinstance(tv, str) and tv else repr(tv) if tv is None else '<non-jwt>'}")
    elif isinstance(v, str) and ('KEY' in k.upper() or 'TOKEN' in k.upper()):
        print(f"{k}: <set, len {len(v)}, prefix {v[:3]}>")
    else:
        print(f"{k}: {v!r}")
PY
echo "=== shell profiles exporting OPENAI/CODEX vars (names only) ==="
for f in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.zshenv" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.profile"; do
  [ -f "$f" ] && grep -nE '(OPENAI|CODEX)[A-Z_]*' "$f" | sed -E 's/=.*/=<value hidden>/' | sed "s|^|$f:|"
done
echo "=== login status ==="
"$CODEX" login status 2>&1 | head -10
echo "=== recent log errors ==="
ls -la "$CH/log" 2>/dev/null
L=$(ls -t "$CH"/log/*.log 2>/dev/null | head -1)
[ -n "$L" ] && grep -iE 'unauthori|401|403|refresh|token_expired|invalid' "$L" | tail -25 | cut -c1-300
echo "=== done ==="
