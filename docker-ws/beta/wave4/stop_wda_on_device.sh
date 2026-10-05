#!/bin/bash
# Stop only Appium's WebDriverAgent xcodebuild (and its children) whose -destination is the given iPhone.
#   stop_wda_on_device.sh <udid>
U=$1
for p in $(pgrep -f "WebDriverAgent.xcodeproj.*-destination id=$U"); do
  kids=$(pgrep -P "$p" | tr '\n' ' ')
  echo "stopping WDA xcodebuild $p (children: $kids) on $U"
  kill $kids "$p" 2>/dev/null; sleep 2; kill -9 $kids "$p" 2>/dev/null
done
pgrep -fl "WebDriverAgent.xcodeproj.*-destination id=$U" || echo "no WDA left on $U"
