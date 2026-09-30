#!/bin/bash
# Final stop: remove ONLY the all-tests run's owned TURN fixture container.
n=mknoon-all-tests-foreground-turn-4a6a560b
docker rm -f "$n" 2>&1; docker ps -a --format '{{.Names}}' | grep -c "^$n$"
