#!/bin/bash
# Print the tail of the plan 406 bindings log, read on the Mac (the container view lags).
tail -${1:-25} /Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/${2:-g406_bindings}.log
