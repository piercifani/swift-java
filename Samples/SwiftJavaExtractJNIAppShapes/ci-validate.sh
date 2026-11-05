#!/bin/bash

set -x
set -e

# FIXME: disable prebuilts until prebuilt swift-syntax isn't broken on 6.2 anymore: https://github.com/swiftlang/swift-java/issues/418
SWIFT_JAVA_BUILD=1 swift build --disable-experimental-prebuilts --disable-sandbox

./gradlew test

# The same modules build for iOS without swift-java, as an app sharing them with iOS does.
if [ "$(uname)" = "Darwin" ]; then
  xcodebuild -scheme SwiftJavaExtractJNIAppShapes -destination 'generic/platform=iOS Simulator' -quiet build
fi
