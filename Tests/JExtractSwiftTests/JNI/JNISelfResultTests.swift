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

/// `Self` as a result of a struct's, an enum's or a class's member is the type itself.
@Suite
struct JNISelfResultTests {
  @Test
  func selfResults_areTheEnclosingType() throws {
    try assertOutput(
      input: """
        public struct Market {
          public static func standard(id: String) -> Self { Market() }
          public func copy() -> Self? { self }
        }
        public enum Kind {
          case a
          public static func make() -> Self { .a }
        }
        """,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public static Market standard(java.lang.String id, SwiftArena swiftArena) {",
        "public java.util.Optional<Market> copy(SwiftArena swiftArena) {",
        "public static Kind make(SwiftArena swiftArena) {",
      ]
    )
  }

  @Test
  func protocolSelf_staysUnresolved() throws {
    try assertOutput(
      input: """
        public protocol Copyable {
          func copy() -> Self
        }
        """,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [],
      notExpectedChunks: ["copy("]
    )
  }
}
