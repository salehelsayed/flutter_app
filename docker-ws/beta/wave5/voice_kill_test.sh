#!/bin/bash
kill 18300 18189 2>/dev/null; sleep 2; ps -p 18189,18300 -o pid= | wc -l
