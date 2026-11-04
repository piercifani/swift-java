//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift.org project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift.org project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import JExtractSwiftLib
import SwiftJavaConfigurationShared
import Testing

/// With `optionalsAsNullable`, a declaration's optionals are its wrapped Java types, `null` for `nil`.
@Suite
struct JNINullableOptionalsTests {
  var config: Configuration {
    var config = Configuration()
    config.optionalsAsNullable = true
    return config
  }

  @Test
  func primitiveParameterAndStringResult() throws {
    try assertOutput(
      input: "public func f(count: Int64?) -> String? {}",
      config: config,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public static String f(java.lang.Long count) {",
        "(count == null ? OptionalLong.empty() : OptionalLong.of(count))",
        "Optional<String> result$optional = ",
        "return (result$optional.isPresent()) ? result$optional.get() : null;",
        // The native method is unchanged.
        "private static native java.lang.String $f(byte count_discriminator, long count_value, byte[] result_discriminator$);",
      ]
    )
  }

  @Test
  func primitiveResult() throws {
    try assertOutput(
      input: "public func f() -> Int64? {}",
      config: config,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public static java.lang.Long f() {",
        "return (result$optional.isPresent()) ? result$optional.getAsLong() : null;",
      ]
    )
  }

  @Test
  func jextractedParameterAndResult() throws {
    try assertOutput(
      input: """
        public struct Tag {}
        public func f(tag: Tag?) -> Tag? {}
        """,
      config: config,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public static Tag f(Tag tag, SwiftArena swiftArena) {",
        "Optional.ofNullable(tag).map(Tag::$memoryAddress).orElse(0L)",
      ]
    )
  }

  @Test
  func escapingClosureParametersKeepOptional() throws {
    try assertOutput(
      input: "public func f(_ body: @escaping (Int64?) -> Void) {}",
      config: config,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: ["void apply(OptionalLong _0);"]
    )
  }

  @Test
  func optionalWithoutTheOption() throws {
    try assertOutput(
      input: "public func f(count: Int64?) -> String? {}",
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: ["public static Optional<String> f(OptionalLong count) {"]
    )
  }
}
