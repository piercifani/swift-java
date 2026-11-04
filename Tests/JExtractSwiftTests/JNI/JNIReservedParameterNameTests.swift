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

/// A parameter named like the thunk's own parameters and locals is renamed; its argument label isn't.
@Suite
struct JNIReservedParameterNameTests {
  let source =
    """
    public struct Outcome {}

    public struct Pitch {
      public init(result: Outcome?, environment: String) {}
    }
    """

  @Test
  func swiftThunks() throws {
    try assertOutput(
      input: source,
      .jni,
      .swift,
      expectedChunks: [
        "result_: jlong, environment_: jstring?) -> jlong {",
        "Pitch.init(result: result_$?.pointee, environment: String(fromJNI: environment_, in: environment))",
      ]
    )
  }

  @Test
  func javaBindings() throws {
    try assertOutput(
      input: source,
      .jni,
      .java,
      expectedChunks: [
        "public static Pitch init(java.util.Optional<Outcome> result_, java.lang.String environment_, SwiftArena swiftArena) {"
      ]
    )
  }
}
