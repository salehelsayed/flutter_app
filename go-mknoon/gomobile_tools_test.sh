#!/bin/bash
# `make gomobile-tools` installs gomobile and gobind only when they are missing
# or the pinned golang.org/x/mobile version or Go toolchain changed. The ensure
# scripts call it before every build; a needless reinstall cost up to 5 min.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/mod" "$tmp/fake"
cp "$here/Makefile" "$here/go.mod" "$tmp/mod/"
cat >"$tmp/fake/go" <<'GO'
#!/bin/bash
echo "go $*" >>"$FAKE_GO_LOG"
if [ "${1:-}" = install ]; then
  mkdir -p "$GOBIN"
  for tool in gomobile gobind; do printf '#!/bin/sh\n' >"$GOBIN/$tool"; chmod +x "$GOBIN/$tool"; done
fi
GO
chmod +x "$tmp/fake/go"
export FAKE_GO_LOG="$tmp/go.log" PATH="$tmp/fake:$PATH"
fail() { echo "FAIL: $1"; exit 1; }
installs() { grep -c '^go install' "$FAKE_GO_LOG" 2>/dev/null || true; }
run() { make -s -C "$tmp/mod" gomobile-tools >/dev/null 2>&1 || fail "make gomobile-tools failed ($1)"; }

run first
[ "$(installs)" = 1 ] || fail 'the first run did not install the tools'
run second
[ "$(installs)" = 1 ] || fail 'tools already at the pinned version were installed again'

rm "$tmp/mod/bin/tools/gobind"
run missing
[ "$(installs)" = 2 ] || fail 'a missing gobind was not installed'

sed -i.bak 's#^\(\tgolang.org/x/mobile\) v[^ ]*#\1 v0.0.0-20990101000000-000000000000#' "$tmp/mod/go.mod"
grep -q 'golang.org/x/mobile v0.0.0-20990101000000-000000000000' "$tmp/mod/go.mod" || fail 'fixture could not change the pin'
run bumped
[ "$(installs)" = 3 ] || fail 'a new golang.org/x/mobile pin did not reinstall'
run bumped-again
[ "$(installs)" = 3 ] || fail 'the new pin was installed twice'

echo 'GOMOBILE_TOOLS_SKIP_PASS'
