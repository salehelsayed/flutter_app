#!/bin/bash
# VC-014 read-only: error text of a devicectl apps query on the iPhone 13.
timeout 60 xcrun devicectl device info apps --device 00008110-00184D622289801E --bundle-id com.mknoon.app 2>&1 | tail -8 | cut -c1-220
