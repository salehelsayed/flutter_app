#!/bin/bash
# From an open Mknoon chat on Android: Add attachment > Media Library > search-pick <file>, optional private mode, optional caption, send.
#   step2_send_media.sh <serial> <file-name> <mode: keep|protected|once> [caption-without-spaces]
S="$1"; F="$2"; M="$3"; C="$4"; D="$(dirname "$0")"; U="bash $D/setA_ui.sh"
$U tap "$S" 'Add attachment' >/dev/null || exit 3; sleep 3
$U tap "$S" 'Media Library' >/dev/null || exit 3; sleep 5
bash "$D/step2_pick_search.sh" "$S" "$F" || exit 3; sleep 6
if [ "$M" != keep ]; then
  $U tap "$S" 'Change&#10;' >/dev/null || { echo "no privacy chip"; exit 4; }; sleep 3
  case "$M" in
    protected) $U tap "$S" 'Protected view&#10;' >/dev/null; sleep 1; $U tap "$S" 'Use Protected view' >/dev/null ;;
    once) $U tap "$S" 'View once&#10;' >/dev/null; sleep 1; $U tap "$S" 'Use View once' >/dev/null ;;
  esac
  sleep 2
fi
$U texts "$S" | grep -E 'Change&#10;' | head -1
if [ -n "$C" ]; then $U send "$S" "$C"; else $U tap "$S" 'content-desc="Send message"' >/dev/null || exit 5; echo "SENT $(date -u +%FT%T)"; fi
echo "file $F mode $M"
