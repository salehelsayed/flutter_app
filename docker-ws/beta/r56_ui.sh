#!/bin/bash
# Pixel UI helper without Maestro: dump (texts/descs with bounds), tap x y, start app, shot name.
. "$(dirname "$0")/beta_env.sh"
A="$ADB -s 21071FDF600CSC"
case "$1" in
  dump) $A shell uiautomator dump /sdcard/r56.xml >/dev/null 2>&1; $A shell cat /sdcard/r56.xml | tr '>' '\n' | grep -oE '(text|content-desc|resource-id)="[^"]+"[^/]*bounds="[^"]+"' | grep -vE 'text="" |content-desc="" ' | sed -E 's/ (class|package|checkable|checked|clickable|enabled|focusable|focused|scrollable|long-clickable|password|selected|index|NAF)="[^"]*"//g' | head -${2:-60} ;;
  tap) $A shell input tap "$2" "$3"; echo tapped ;;
  start) $A shell monkey -p com.mknoon.app -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; echo started ;;
  back) $A shell input keyevent 4; echo back ;;
  shot) bash "$(dirname "$0")/r48_px_shot.sh" "$2" ;;
esac
