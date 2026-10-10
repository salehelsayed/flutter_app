#!/bin/bash
# Plan 406: the two relay integration tests that need Docker / git, on the Mac
# (main checkout, go1.27.1). Self-detaches; log g406_relay_docker_tests.log.
set -u
W=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5
OUT=$W/g406_relay_docker_tests.log
if [ -z "${G406RD_DETACHED:-}" ]; then
  G406RD_DETACHED=1 nohup bash "$0" "$@" >"$OUT" 2>&1 &
  echo "detached pid $! log $OUT"; exit 0
fi
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/local/go/bin:/Applications/Docker.app/Contents/Resources/bin:$PATH"
cd /Volumes/CrucialX9/flutter_app/go-relay-server || exit 1
echo "docker: $(docker info --format '{{.ServerVersion}}' 2>&1 | head -1)"
git log --oneline -1
GOTOOLCHAIN=go1.27.1 go test -tags integration . -count=1 -v -timeout 20m \
  -run '^(TestProductionAudioCallDeviceFixture_ProductionRelayTurnCredentialsCoturnAndTeardown|TestRedisAckCustodySurvivesRelayProcessHandoffKillSwitchAndLegacyNamespace)$' 2>&1 \
  | grep -E "^(=== RUN|--- |PASS|FAIL|ok )|_test\.go:[0-9]+:" | head -40
echo "RELAY DOCKER TESTS EXIT=${PIPESTATUS[0]}"
