#!/bin/bash
pgrep -fl "mknoon_checks.py run" | cut -c1-120
pgrep -fl "sims.dart|run_production_startup_resume|flutter_tools.snapshot build|gradle" | cut -c1-140 | head -5
