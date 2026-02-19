#!/bin/bash
# Bundle the JS code for Flutter

set -e

cd "$(dirname "$0")"

echo "Installing dependencies..."
npm install

echo "Building bundle..."
npm run build

echo ""
echo "Bundle created at: ../assets/js/core_lib.js"
ls -la ../assets/js/core_lib.js
