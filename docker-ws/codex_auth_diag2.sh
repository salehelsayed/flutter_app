#!/bin/bash
# Read-only Codex CLI auth diagnostic, part 2. Prints no secret values.
CH="$HOME/.codex"
tmo() { perl -e 'alarm shift; exec @ARGV' "$@"; }
redact() { sed -E 's/((KEY|TOKEN|SECRET|PASS)[A-Za-z_]*[[:space:]]*=[[:space:]]*).*/\1<redacted>/I'; }
echo "=== .zshrc 108-130 ==="; sed -n '108,130p' "$HOME/.zshrc" | redact
echo "=== .zshenv ==="; redact < "$HOME/.zshenv"
echo "=== config.toml top-level (non-project) ==="
grep -vE '^\[projects\.|^trust_level|^$' "$CH/config.toml" | redact | head -80
echo "=== package ==="
ls -la "$HOME/.local/lib/node_modules/@openai/"
grep -m1 '"version"' "$HOME/.local/lib/node_modules/@openai/codex/package.json"
echo "=== zsh (non-interactive, .zshenv only) env ==="
tmo 20 zsh -c 'env | grep -E "^(OPENAI|CODEX)[A-Z_]*=" | sed -E "s/=(.{8}).*/=<set, prefix \1>/"' </dev/null 2>&1
echo "=== zsh interactive env ==="
tmo 30 zsh -i -c 'echo "CODEX_HOME=${CODEX_HOME:-<unset>}"; env | grep -E "^(OPENAI|CODEX)[A-Z_]*=" | sed -E "s/=(.{8}).*/=<set, prefix \1>/"; whence -a codex' </dev/null 2>&1 | grep -v '^$' | tail -15
echo "=== recent auth errors in logs_2.sqlite ==="
tmo 60 python3 - "$CH/logs_2.sqlite" <<'PY'
import sqlite3, sys
db = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
tabs = [r[0] for r in db.execute("select name from sqlite_master where type='table'")]
print("tables:", tabs)
for t in tabs:
    cols = [(r[1], r[2]) for r in db.execute(f"pragma table_info('{t}')")]
    print(t, cols)
    text = [c for c, ty in cols if 'TEXT' in (ty or '').upper() or ty == '']
    if not text: continue
    mx = db.execute(f"select max(rowid) from '{t}'").fetchone()[0] or 0
    cond = " or ".join(f"{c} like '%nauthori%' or {c} like '%401%' or {c} like '%token_expired%' or {c} like '%refresh_token%'" for c in text)
    rows = db.execute(f"select rowid,* from '{t}' where rowid > {mx-300000} and ({cond}) order by rowid desc limit 12").fetchall()
    for r in rows:
        s = " | ".join(str(x) for x in r)
        print("  ", s[:400])
PY
echo "=== done ==="
