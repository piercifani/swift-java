#!/bin/bash

set -x
set -e

# FIXME: disable prebuilts until prebuilt swift-syntax isn't broken on 6.2 anymore: https://github.com/swiftlang/swift-java/issues/418
swift build --disable-experimental-prebuilts --disable-sandbox

./gradlew test
