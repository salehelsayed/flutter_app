#!/bin/bash
# Opens the orbit depth playground in the Mac's default browser.
cd "$(dirname "$0")/../.."
open "prototypes/orbit_depth/depth_playground.html" && echo "opened $(pwd)/prototypes/orbit_depth/depth_playground.html"
