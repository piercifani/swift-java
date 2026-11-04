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
import CodePrinting
import JExtractSwiftLib
import SwiftJavaConfigurationShared
import Testing

/// `closureMethodName` names the method of closure interfaces, so Kotlin can call `onTap()` with `invoke`.
@Suite
struct JNIClosureMethodNameTests {
  let source =
    """
    public struct Item {}

    public final class Notifier {
      public var onItem: (Item) -> Void
      public init(onItem: @escaping (Item) -> Void) { self.onItem = onItem }
      public func double(_ f: (Int64) -> Int64) -> Int64 { f(2) }
    }
    """

  var config: Configuration {
    var config = Configuration()
    config.closureMethodName = "invoke"
    return config
  }

  @Test
  func javaInterfacesUseTheName() throws {
    try assertOutput(
      input: source,
      config: config,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "void invoke(Item _0);",
        // A closure `java.util.function` covers gets its own interface, so it can be called the same way.
        "long invoke(long _0);",
      ],
      notExpectedChunks: [
        " apply(",
        "LongUnaryOperator",
      ]
    )
  }

  @Test
  func swiftCallsTheName() throws {
    try assertOutput(
      input: source,
      config: config,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public func invoke(_ _0: JavaItem?)"
      ],
      notExpectedChunks: [
        "func apply(",
        ".apply(",
      ]
    )
  }
}
