#!/bin/bash
# Refuse unless all three package variables name the same disposable com.mknoon.sims.* package.
set -u
first="${ANDROID_APP_PACKAGE:-}"
for name in ANDROID_APP_PACKAGE SIMS_APP_ID ORG_GRADLE_PROJECT_androidApplicationId; do
  value="${!name:-}"
  if [ -z "$value" ] || [ "$value" = "com.mknoon.app" ] || [ "$value" != "$first" ] \
      || ! [[ "$value" =~ ^com\.mknoon\.sims\.[a-z_]+$ ]]; then
    echo "x1 package guard refused: $name" >&2
    exit 2
  fi
done
exit 0
