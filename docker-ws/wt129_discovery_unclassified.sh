#!/bin/bash
# In build/wt-translate-129: list unclassified candidates of the reliability simulation discovery.
# Runs a temporary copy with the failure exit removed (the real script exits before printing them), then deletes it.
#   host-run bash docker-ws/wt129_discovery_unclassified.sh
cd /Volumes/CrucialX9/flutter_app/build/wt-translate-129 || exit 2
T=scripts/.tmp_discovery_list.sh
sed 's/^  emit_failures_if_any "\$unclassified_count" 0$/  true/' scripts/check_reliability_simulation_discovery.sh > "$T"
bash "$T" --classifications-tsv 2>/dev/null | awk -F '\t' '$1=="unclassified"{print $2"\t"$3}'
rm -f "$T"
