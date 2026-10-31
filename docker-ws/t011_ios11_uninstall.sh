#!/bin/bash
# TRANSFER-011 cleanup: remove com.mknoon.app from the iPhone 11 ONLY (it was not installed before this run).
timeout 120 xcrun devicectl device uninstall app --device 00008030-001A6D2801BB802E com.mknoon.app 2>&1 | tail -2
