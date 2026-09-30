#!/bin/bash
# Read-only: can the installed Maestro/Appium serve MCP, and what is available?
. "$(dirname "$0")/beta_env.sh"
echo "--- maestro"; maestro --version 2>/dev/null; maestro --help 2>&1 | grep -iE "^\s+mcp|mcp " | head -3
maestro mcp --help 2>&1 | head -8
echo "--- appium"; appium --version 2>/dev/null; appium driver list --installed 2>&1 | grep -E "xcuitest|uiautomator2" | head -2
echo "--- appium mcp package on npm"; npm view appium-mcp name version description 2>&1 | head -4
echo "--- stdio-to-http bridge on npm"; npm view supergateway version 2>&1 | head -1
echo "--- node"; node --version
