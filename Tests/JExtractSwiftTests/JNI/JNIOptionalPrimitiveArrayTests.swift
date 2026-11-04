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

/// An optional array of primitives wraps the primitive array the native method returns.
@Suite
struct JNIOptionalPrimitiveArrayTests {
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
}
