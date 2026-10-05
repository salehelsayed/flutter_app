#!/bin/bash
# Read-only: session create/delete history in the Appium MCP log today, and what the other xcodebuild/appium-qa run.
L=~/tools/mcp/logs/appium-mcp.log
grep -nE "session created|Deleting|deleted|delete|Removing session|SIGTERM|shutting|Starting appium-mcp|listening|stdio|new client|Closing" "$L" | tail -30 | cut -c1-200
echo "== other xcodebuild:"; ps -o pid,lstart,command -p 74643 | cut -c1-400
