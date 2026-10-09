#!/bin/bash
# Read-only: Mknoon build on the USB iPhone 13.
xcrun devicectl device info apps --device ${1:-00008110-00184D622289801E} --bundle-id com.mknoon.app 2>&1 | tail -4
