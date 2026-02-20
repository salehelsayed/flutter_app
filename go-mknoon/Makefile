.PHONY: ios android all clean test

MODULE := github.com/mknoon/go-mknoon
BIND_PKG := $(MODULE)/bridge

# Output paths relative to the Flutter project
IOS_OUT := ../ios/Runner/GoMknoon.xcframework
ANDROID_OUT := ../android/app/libs/GoMknoon.aar

# Android min API level (matches Flutter minSdk)
ANDROID_API ?= 24

# Go ≥1.23 restricts //go:linkname; wlynxg/anet needs the check disabled.
ANDROID_LDFLAGS := -checklinkname=0

# Auto-detect NDK if ANDROID_NDK_HOME is not set.
# Picks the highest version under $ANDROID_HOME/ndk/.
ifndef ANDROID_NDK_HOME
  ifdef ANDROID_HOME
    ANDROID_NDK_HOME := $(shell ls -d $(ANDROID_HOME)/ndk/*/ 2>/dev/null | sort -V | tail -1)
  endif
endif

all: ios android

ios:
	gomobile bind -target=ios -o $(IOS_OUT) $(BIND_PKG)

android:
	ANDROID_NDK_HOME=$(ANDROID_NDK_HOME) \
	gomobile bind -target=android -androidapi $(ANDROID_API) \
		-ldflags "$(ANDROID_LDFLAGS)" -o $(ANDROID_OUT) $(BIND_PKG) \
	|| { rm -f $(ANDROID_OUT); exit 1; }

clean:
	rm -rf $(IOS_OUT) $(ANDROID_OUT) GoMknoon-sources.jar

test:
	go test ./...
