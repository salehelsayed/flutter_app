.PHONY: ios android all clean test

MODULE := github.com/mknoon/go-mknoon
BIND_PKG := $(MODULE)/bridge

# Output paths relative to the Flutter project
IOS_OUT := ../ios/Runner/GoMknoon.xcframework
ANDROID_OUT := ../android/app/libs/GoMknoon.aar

all: ios android

ios:
	gomobile bind -target=ios -o $(IOS_OUT) $(BIND_PKG)

android:
	gomobile bind -target=android -o $(ANDROID_OUT) $(BIND_PKG)

clean:
	rm -rf $(IOS_OUT) $(ANDROID_OUT) GoMknoon-sources.jar

test:
	go test ./...
