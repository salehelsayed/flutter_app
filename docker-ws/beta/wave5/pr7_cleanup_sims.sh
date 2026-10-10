#!/bin/bash
# Shut down the two PR 7 simulators and report the size of the two build worktrees.
xcrun simctl shutdown 8E31AD68-4DBF-4336-AEBF-18148DC9FA07 2>/dev/null
xcrun simctl shutdown DBE8C32E-9F19-4593-860A-B41113791D79 2>/dev/null
xcrun simctl list devices booted | grep -c Booted
du -sh /Volumes/CrucialX9/flutter_app-pr7-fix /Volumes/CrucialX9/flutter_app-pr7-main 2>/dev/null
