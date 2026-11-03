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
import SwiftExtract
import SwiftJavaConfigurationShared
import Testing

/// Trailing default arguments become Java overloads that leave them out; Swift fills them in.
@Suite
struct JNIDefaultArgumentsTests {
  let source = "public func greet(name: String, excited: Bool = false, times: Int32 = 1) -> String {}"

  @Test
  func javaOverloads() throws {
    try assertOutput(
      input: source,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public static java.lang.String greet(java.lang.String name, boolean excited, int times) {",
        "public static java.lang.String greet(java.lang.String name, boolean excited) {",
        "public static java.lang.String greet(java.lang.String name) {",
        "private static native java.lang.String $greet(java.lang.String name);",
      ]
    )
  }

  @Test
  func swiftCallsLeaveTheArgumentsOut() throws {
    try assertOutput(
      input: source,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "return SwiftModule.greet(name: String(fromJNI: name, in: environment), excited: Bool(fromJNI: excited, in: environment)).getJNILocalRefValue(in: environment)",
        "return SwiftModule.greet(name: String(fromJNI: name, in: environment)).getJNILocalRefValue(in: environment)",
      ]
    )
  }

  @Test
  func initializers() throws {
    try assertOutput(
      input: """
        public struct Point {
          public init(x: Int64 = 0, y: Int64 = 0) {}
        }
        """,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public static Point init(long x, SwiftArena swiftArena) {",
        "public static Point init(SwiftArena swiftArena) {",
      ]
    )
  }

  @Test
  func declaredOverloadsWin() throws {
    var config = Configuration()
    config.swiftModule = "SwiftModule"
    let translator = makeSwiftJavaAnalyzer(config: config)
    try translator.analyze(
      path: "/fake/Fake.swiftinterface",
      text: """
        public func f(a: Int64 = 0) {}
        public func f() {}
        """
    )
    var analysis = translator.result
    analysis.expandDefaultArgumentOverloads()
    // `f()` is declared, so `f(a:)` adds no overload without `a`.
    #expect(analysis.extractedGlobalFuncs.map(\.functionSignature.parameters.count) == [1, 0])
  }

  @Test
  func onlyTrailingDefaults() throws {
    try assertOutput(
      input: "public func f(a: Int64 = 0, b: Int64) {}",
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: ["public static void f(long a, long b) {"],
      notExpectedChunks: ["public static void f(long a) {", "public static void f() {"]
    )
  }
}
