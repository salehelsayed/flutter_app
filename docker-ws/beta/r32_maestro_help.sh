#!/bin/bash
. "$(dirname "$0")/beta_env.sh"
maestro --version 2>&1 | tail -1; maestro test --help 2>&1 | grep -iE 'driver|reinstall|port' | head
