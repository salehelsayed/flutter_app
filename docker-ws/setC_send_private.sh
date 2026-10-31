#!/bin/bash
# From an open Mknoon 1:1 chat on Android: attach <file> from Media Library, choose private <mode> (keep|protected|once|1h), send.
#   setC_send_private.sh <serial> <file-name> <mode>
S="$1"; F="$2"; M="$3"; D="$(dirname "$0")"; U="bash $D/setA_ui.sh"
$U tap "$S" 'Add attachment' >/dev/null || exit 3; sleep 3
$U tap "$S" 'Media Library' >/dev/null || exit 3; sleep 5
bash "$D/setC_pick.sh" "$S" "$F" || exit 3; sleep 5
if [ "$M" != keep ]; then
  $U tap "$S" 'Change&#10;' >/dev/null || exit 4; sleep 3
  case "$M" in
    protected) $U tap "$S" 'Protected view&#10;' >/dev/null; sleep 1; $U tap "$S" 'Use Protected view' >/dev/null ;;
    once) $U tap "$S" 'View once&#10;' >/dev/null; sleep 1; $U tap "$S" 'Use View once' >/dev/null ;;
    1h) $U tap "$S" 'Set an expiry&#10;' >/dev/null; sleep 2; $U tap "$S" 'content-desc="1 hour"' >/dev/null; sleep 1; $U tap "$S" 'Use Set an expiry' >/dev/null ;;
  esac
  sleep 2
fi
$U texts "$S" | grep -E 'Change&#10;' | head -1
$U tap "$S" 'content-desc="Send message"' >/dev/null || exit 5
echo "SENT $F $M $(date -u +%T)"
