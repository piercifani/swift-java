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

/// An `@autoclosure` parameter takes a Java lambda; the thunk passes a call to it as the argument.
@Suite
struct JNIAutoclosureTests {
  @Test
  func escapingAutoclosure_swiftThunks() throws {
    try assertOutput(
      input: """
        public struct Scheme {}
        public func configure(scheme: @autoclosure @escaping () -> Scheme) {}
        """,
      .jni,
      .swift,
      expectedChunks: [
        "let scheme$autoclosure = {",
        "SwiftModule.configure(scheme: scheme$autoclosure())",
      ]
    )
  }
}
