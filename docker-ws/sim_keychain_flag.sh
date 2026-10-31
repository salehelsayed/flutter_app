#!/bin/bash
# Read-only: count keychain items whose account is the given key in a simulator's keychain DB (no values read).
#   host-run bash docker-ws/sim_keychain_flag.sh <sim-udid> <account>
DB="$HOME/Library/Developer/CoreSimulator/Devices/${1:?udid}/data/Library/Keychains/keychain-2-debug.db"
[ -f "$DB" ] || { echo "no keychain db"; exit 2; }
T=$(mktemp -d); cp "$DB"* "$T/" 2>/dev/null
echo "rows_with_account=$(sqlite3 "$T/keychain-2-debug.db" "select count(*) from genp where cast(acct as text)='${2:?account}';" 2>&1)"
echo "total_genp=$(sqlite3 "$T/keychain-2-debug.db" 'select count(*) from genp;' 2>&1)"
rm -rf "$T"
