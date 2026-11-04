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
import Testing

/// Swift `Error` values cross as Java `Throwable`s.
@Suite
struct JNIErrorValuesTests {
  let source =
    """
    public func lastError() -> Error? { nil }
    public func describe(_ error: any Error) -> String { "" }
    public func wrap(_ error: Error?) -> Error? { error }
    public func onDone(_ cb: @escaping (Error?) -> Void) {}
    public func onFail(_ cb: @escaping (any Error) -> Void) {}
    public func makeHandler() -> (Error) -> String { { _ in "" } }
    """

  @Test
  func javaSignatures() throws {
    try assertOutput(
      input: source,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public static java.util.Optional<java.lang.Throwable> lastError() {",
        "public static java.lang.String describe(java.lang.Throwable error) {",
        "public static java.util.Optional<java.lang.Throwable> wrap(java.util.Optional<java.lang.Throwable> error) {",
        "void apply(java.util.Optional<java.lang.Throwable> _0);",
        "void apply(java.lang.Throwable _0);",
        "java.lang.String apply(java.lang.Throwable _0);",
      ]
    )
  }

  @Test
  func swiftConversions() throws {
    try assertOutput(
      input: source,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "return (SwiftModule.lastError()).flatMap { environment.makeJavaThrowableLocalRef(for: $0) }",
        "return SwiftModule.describe(environment.makeSwiftError(for: error!)).getJNILocalRefValue(in: environment)",
        "return (SwiftModule.wrap(error.map { environment.makeSwiftError(for: $0) })).flatMap { environment.makeJavaThrowableLocalRef(for: $0) }",
        // Closures implemented in Java get SwiftJava's `Throwable`.
        "public func apply(_ _0: JavaOptional<Throwable>?)",
        "public func apply(_ _0: Throwable?)",
        "javaInterface_cb$.apply(_makeThrowable(for: _0))",
        // A closure returned to Java converts with `ErrorBridge`.
        "closure$(ErrorBridge.fromJavaObject(_swiftClosureArgument(arguments$, 0, in: environment), in: environment))",
      ]
    )
  }
}
