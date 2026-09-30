#!/bin/bash
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
echo "--- java"; /usr/bin/java -version 2>&1 | head -2; /usr/libexec/java_home -V 2>&1 | head -5
echo "--- brew"; command -v brew; 
echo "--- node"; node -v; npm -v; npm config get prefix
echo "--- ~/.appium"; ls ~/.appium/node_modules | head -20; ls ~/.appium/node_modules/.bin 2>/dev/null | head
echo "--- npm global"; npm ls -g --depth=0 2>/dev/null | head -20
