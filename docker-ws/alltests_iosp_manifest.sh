#!/bin/bash
# Read-only: show define-related keys (names only / non-secret) from the prepared iOS production bundle manifest.
m="/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/prepared/ios.device.production.bundle/bundle_manifest.json"
ls -la "$m"
grep -o -E '"[A-Za-z_]*([Dd]efine|AUTO_SETUP|E2E_TEST_MODE|SIMS_BUILD_PROFILE_ID)[A-Za-z_]*"[^,}]{0,120}' "$m" | head -20
grep -o -E 'AUTO_SETUP_USERNAME[^",]{0,3}|E2E_TEST_MODE=[a-z]*|SIMS_BUILD_PROFILE_ID=[a-z.]*' "$m" | sort | uniq -c | head
