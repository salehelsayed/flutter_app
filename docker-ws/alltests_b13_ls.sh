#!/bin/bash
ls -la "/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/notifications.android_payload_campaign/" | grep -viE 'run-env|private' | head -60
