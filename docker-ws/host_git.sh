#!/bin/bash
# Run a git command on the Mac. The container has no GitHub credentials and
# the host bridge only executes repo scripts, so pushes go through this.
# Usage: /claude-host-bin/host-run bash docker-ws/host_git.sh -C <mac path> <git args...>
exec git "$@"
