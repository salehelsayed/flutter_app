#!/bin/bash
# Lists Mac git processes and any owner of the repository index lock.
ps -axo pid,etime,command | grep -E "[g]it( |$)" | cut -c1-160
lsof /Volumes/CrucialX9/flutter_app/.git/index.lock 2>/dev/null
ls -la /Volumes/CrucialX9/flutter_app/.git/index.lock 2>&1
