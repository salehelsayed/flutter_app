.PHONY: build run test test-notifications clean tidy lint

build:
	go build -o relay-server .

run: build
	./relay-server

test:
	go test ./... -count=1

test-notifications:
	go test ./... -run '^TestRelayNotificationClosure_' -count=1

tidy:
	go mod tidy

# Go hygiene gate. gofmt -l only LISTS unformatted files, so wrap it to fail; go vet is the closest analogue to `flutter analyze`.
# golangci-lint lints only code changed since LINT_BASE (default HEAD = uncommitted work) so pre-existing
# branch debt is not flooded — lint your FDC work before committing it.
# NOTE: do NOT base this on `main` — `new-orbit` is well ahead of main, so a main delta floods legacy
# code. To lint a whole FDC slice, pass the SHA you branched that work from: `make lint LINT_BASE=<sha>`.
# Requires golangci-lint installed (brew install golangci-lint).
LINT_BASE ?= HEAD
lint:
	@test -z "$$(gofmt -l .)" || { echo "gofmt -l: unformatted files (run gofmt -w):"; gofmt -l .; exit 1; }
	go vet ./...
	@command -v golangci-lint >/dev/null 2>&1 || { echo "golangci-lint not installed — https://golangci-lint.run/welcome/install/ (brew install golangci-lint)"; exit 1; }
	golangci-lint run --new-from-rev=$(LINT_BASE) ./...

clean:
	rm -f relay-server
