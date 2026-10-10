#!/bin/bash
cd /Volumes/CrucialX9/flutter_app
echo "== result file"; cat docker-ws/build_store_release_result.txt
echo "== log tail"; tail -c 1500 docker-ws/beta/wave5/release122_build.log | tr "\r" "\n" | grep -v "^ *$" | tail -12
