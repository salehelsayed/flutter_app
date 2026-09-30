#!/bin/bash
# Compile-check and vet go-mknoon/node in the main checkout.
cd /Volumes/CrucialX9/flutter_app/go-mknoon || exit 4
export GOTOOLCHAIN=go1.25.0
go build ./node/ && go vet ./node/ && echo BUILD_VET_OK
