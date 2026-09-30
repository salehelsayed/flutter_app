#!/bin/bash
# save|restore the Mknoon APK another session installed on the Pixel emulator (app data is kept either way).
#  save:    pull the installed APK to $BETA/other-session-apk/<versionName>.apk, unless it is one of my beta builds
#           (1.0.0-06d5ab570.d<N>.t<stamp>); last.txt names the most recent save
#  restore: reinstall the most recently saved APK in place and print the installed version
. "$(dirname "$0")/beta_env.sh"
D="$BETA/other-session-apk"; mkdir -p "$D"
case "$1" in
  save)
    v=$($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r' | sed 's/versionName=//')
    case "$v" in 1.0.0-06d5ab570.d[0-9]*.t[0-9]*) echo "installed is my beta build ($v): nothing to save"; exit 0 ;; esac
    p=$($ADB shell pm path $PKG | tr -d '\r' | sed -n 's/^package://p' | head -1)
    $ADB pull "$p" "$D/$v.apk" > /dev/null 2>&1
    $ADB shell dumpsys package $PKG | grep -E 'versionName|versionCode|lastUpdateTime' | tr -d '\r' > "$D/$v.version.txt"
    echo "$v" > "$D/last.txt"
    echo "saved $v from $p: $(stat -f %z "$D/$v.apk" 2>/dev/null) bytes, device $($ADB shell stat -c %s "$p" | tr -d '\r') bytes"
    ;;
  restore)
    v=$(cat "$D/last.txt" 2>/dev/null); f="$D/$v.apk"
    [ -n "$v" ] && [ -f "$f" ] || { f="$D/app.apk"; v="(first save)"; }
    [ -f "$f" ] || { echo "nothing saved"; exit 1; }
    timeout 1800 $ADB push "$f" /data/local/tmp/other-session.apk > /dev/null 2>&1
    echo "pm install $v: $(timeout 900 $ADB shell pm install -r -d /data/local/tmp/other-session.apk 2>&1 | tail -1)"
    $ADB shell rm -f /data/local/tmp/other-session.apk
    echo "installed now: $($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r')"
    ;;
  *) echo "usage: r28_other_apk.sh save|restore"; exit 1 ;;
esac
