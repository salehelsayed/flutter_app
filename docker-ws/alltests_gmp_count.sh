#!/bin/bash
# Read-only: count group multi-party scenario dirs and verdicts from this run (since the run start file).
t=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-tmp; ref=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run/source097-major-legacy/plan.json
dirs=$(find "$t" -maxdepth 1 -type d -name 'group_multi_party_*' -newer "$ref" | wc -l)
verd=$(find "$t" -maxdepth 2 -name '*orchestrator_verdict.json' -newer "$ref" | wc -l)
pass=$(find "$t" -maxdepth 2 -name '*orchestrator_verdict.json' -newer "$ref" -exec grep -l '"pass"\|"PASS"\|"verdict": *"pass"' {} + 2>/dev/null | wc -l)
echo "scenario dirs since run start: $dirs; orchestrator verdicts: $verd; verdicts mentioning pass: $pass"
