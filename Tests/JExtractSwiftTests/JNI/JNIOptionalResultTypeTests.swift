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

/// An optional result wraps the Java value the native method returns.
@Suite
struct JNIOptionalResultTypeTests {
  @Test
  func optionalArrayOfPrimitives_javaBindings() throws {
    try assertOutput(
      input: """
        public struct Targeting {
          public let tabs: [Int64]?
        }
        """,
      .jni,
      .java,
      expectedChunks: [
        "public java.util.Optional<long[]> getTabs() {",
        "private static native long[] $getTabs(long selfPointer, byte[] result_discriminator$);",
      ],
      notExpectedChunks: [
        "java.lang.Long[]"
      ]
    )
  }

  @Test
  func optionalLabeledTuple_javaBindings() throws {
    try assertOutput(
      input: """
        public struct Game {
          public var teamScores: (primary: Int64?, secondary: Int64?)? { nil }
        }
        """,
      .jni,
      .java,
      expectedChunks: [
        "public java.util.Optional<LabeledTuple_getTeamScores_primary_secondary<OptionalLong, OptionalLong>> getTeamScores() {",
        "public static final class LabeledTuple_getTeamScores_primary_secondary<T0, T1>",
      ]
    )
  }
}
