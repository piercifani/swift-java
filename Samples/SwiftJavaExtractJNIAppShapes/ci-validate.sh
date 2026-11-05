#!/bin/bash

set -x
set -e

# FIXME: disable prebuilts until prebuilt swift-syntax isn't broken on 6.2 anymore: https://github.com/swiftlang/swift-java/issues/418
swift build --disable-experimental-prebuilts --disable-sandbox

./gradlew test

# An app sharing these modules with iOS builds them for iOS too.
if [ "$(uname)" = "Darwin" ]; then
  xcodebuild -scheme SwiftJavaExtractJNIAppShapes -destination 'generic/platform=iOS Simulator' -quiet build
fi
