.PHONY: ios android clean test

MODULE := github.com/mknoon/go-mknoon
BIND_PKG := $(MODULE)/bridge

ios:
	gomobile bind -target=ios -o GoMknoon.xcframework $(BIND_PKG)

android:
	gomobile bind -target=android -o GoMknoon.aar $(BIND_PKG)

clean:
	rm -rf GoMknoon.xcframework GoMknoon.aar GoMknoon-sources.jar

test:
	go test ./...
