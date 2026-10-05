#!/bin/bash
# Read-only: Appium MCP server process start time and the tail of its logs.
ps -axo pid,lstart,command | grep -E 'appium-mcp|run-appium-mcp' | grep -v grep | cut -c1-200
ls -la ~/tools/mcp/logs/ 2>/dev/null
for f in $(ls -t ~/tools/mcp/logs/*appium* 2>/dev/null | head -2); do echo "== $f"; tail -25 "$f" | cut -c1-220; done
