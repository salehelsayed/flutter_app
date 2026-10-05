#!/bin/bash
# Read-only: which Appium installs and XCUITest drivers exist on the Mac, and whether node-devicectl is patched.
for a in ~/tools/appium/node_modules/.bin/appium ~/.local/share/appium-qa/node_modules/.bin/appium ~/.local/share/appium-qa/appium-mcp/node_modules/.bin/appium $(command -v appium); do
  [ -x "$a" ] && echo "appium: $a $($a --version 2>/dev/null)"
done
for d in ~/.local/share/appium-qa/appium-mcp/node_modules/appium-xcuitest-driver ~/tools/mcp/node_modules/appium-xcuitest-driver ~/.appium/node_modules/appium-xcuitest-driver; do
  [ -d "$d" ] || continue
  echo "xcuitest at $d $(grep -m1 '"version"' $d/package.json)"
  f=$(grep -rl "BEGINSWITH" $d/node_modules/node-devicectl/build 2>/dev/null | head -1)
  [ -n "$f" ] && echo "  devicectl filter: $(grep -o 'executablePath BEGINSWITH\|executable.path BEGINSWITH' "$f" | head -1)"
done
ls ~/tools/mcp/node_modules/.bin 2>/dev/null | grep -i appium | head
