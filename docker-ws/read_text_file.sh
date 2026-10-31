#!/bin/bash
# Print the first N lines of a text file outside the container's view (read-only).
#   host-run bash docker-ws/read_text_file.sh <file> [lines]
head -n "${2:-80}" "${1:?file}"
