#!/bin/bash
# Show whether the verify container is still running and what docker is doing.
echo "--- docker path: $(command -v docker)"
ps -axo pid,etime,command | awk '/docker run --rm --user/ && !/awk/'
docker ps --format '{{.ID}} {{.Image}} {{.RunningFor}} {{.Command}}' 2>&1 | head
echo PS DONE
