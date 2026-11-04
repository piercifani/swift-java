#!/bin/bash

set -x
set -e

# WORKAROUND: prebuilts broken on Swift 6.2.1 and Linux and tests using macros https://github.com/swiftlang/swift-java/issues/418
if [ "$(uname)" = "Darwin" ]; then
  DISABLE_EXPERIMENTAL_PREBUILTS=''
else
  DISABLE_EXPERIMENTAL_PREBUILTS='--disable-experimental-prebuilts'
fi

if [[ "$(uname)" == "Darwin" && -n "$GITHUB_ACTION" ]]; then
  # WORKAROUND (as in SwiftJavaExtractJNISampleApp): with enableJavaCallbacks the jextract plugin runs
  # Gradle in its own GRADLE_USER_HOME, which times out downloading the wrapper on GitHub's macOS runners.
  ./gradlew -h
  GRADLE_USER_HOME="$(pwd)/.build/plugins/outputs/swiftjavaextractjnikotlinsampleapp/KotlinSampleModels/destination/JExtractSwiftPlugin/gradle-user-home"
  if [ -d "$HOME/.gradle" ] ; then
    mkdir -p "$GRADLE_USER_HOME"
    cp -r "$HOME/.gradle/"* "$GRADLE_USER_HOME/" || true
  fi
fi

# FIXME: disable prebuilts until prebuilt swift-syntax isn't broken on 6.2 anymore: https://github.com/swiftlang/swift-java/issues/418
swift build $DISABLE_EXPERIMENTAL_PREBUILTS --disable-sandbox

./gradlew test
