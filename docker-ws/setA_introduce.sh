#!/bin/bash
# From the chat list on <serial>: open chat <A>, Introduce to your circle, pick only <B>, send, return to the chat list.
#   setA_introduce.sh <serial> <A> <B>
S="$1"; A="$2"; B="$3"; U="bash $(dirname "$0")/setA_ui.sh"
$U tap "$S" "content-desc=\"$A" >/dev/null || exit 3; sleep 3
$U tap "$S" "Conversation options" >/dev/null || exit 3; sleep 2
$U tap "$S" "Introduce to your circle" >/dev/null || exit 3; sleep 3
$U tap "$S" "content-desc=\"$B\"" >/dev/null || exit 3; sleep 1
$U texts "$S" | grep -q 'Introduce (1)' || { echo "selection is not exactly one"; exit 4; }
$U tap "$S" "Introduce (1)" >/dev/null; echo "introduced $(date -u +%T)"; sleep 4
$U texts "$S" | grep -q "1 introduction sent" && echo "confirmation shown"
$U tap "$S" 'content-desc="Back to conversation"' >/dev/null; sleep 3
$U tap "$S" 'content-desc="Back"' >/dev/null; sleep 3
