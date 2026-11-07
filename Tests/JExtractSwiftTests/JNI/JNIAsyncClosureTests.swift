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

/// Async closures implemented in Java return a `CompletableFuture`, which Swift awaits.
@Suite
struct JNIAsyncClosureTests {
  let source =
    """
    public struct Item {
      public var id: String
    }
    public func perform(_ work: @escaping @Sendable (Item) async -> Void) async {}
    public func load(_ fetch: @escaping @Sendable (Int64) async throws -> Item) async throws {}
    public func count(_ f: (Int64) async -> Int64) async {}
    """

  @Test
  func javaInterfaceReturnsFuture() throws {
    try assertOutput(
      input: source,
      .jni,
      .java,
      detectChunkByInitialLines: 2,
      expectedChunks: [
        """
        @FunctionalInterface
        public interface work {
          java.util.concurrent.CompletableFuture<java.lang.Void> apply(Item _0);

          default java.util.concurrent.CompletableFuture<java.lang.Void> invoke(Item _0) {
            return apply(_0);
          }
        }
        """,
        """
        @FunctionalInterface
        public interface fetch {
          java.util.concurrent.CompletableFuture<Item> apply(long _0);

          default java.util.concurrent.CompletableFuture<Item> invoke(long _0) {
            return apply(_0);
          }
        }
        """,
        // Not `LongUnaryOperator`: a non-escaping async closure gets its own interface too.
        """
        @FunctionalInterface
        public interface f {
          java.util.concurrent.CompletableFuture<java.lang.Long> apply(long _0);

          default java.util.concurrent.CompletableFuture<java.lang.Long> invoke(long _0) {
            return apply(_0);
          }
        }
        """,
      ]
    )
  }

  @Test
  func swiftAwaitsTheFuture() throws {
    try assertOutput(
      input: source,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        @JavaInterface("com.example.swift.SwiftModule$perform$work")
        public struct JavaSwiftModule_perform_work {
          @JavaMethod
          public func apply(_ _0: JavaItem?) -> JavaCompletableFuture!
        }
        """,
        """
        let returnedFuture$ = try! javaInterface_work$call.dynamicJavaMethodCall(methodName: "apply", arguments: _0Class.wrapMemoryAddressUnsafe(Int64(Int(bitPattern: _0Pointer))), resultType: JavaCompletableFuture?.self)
        guard let returnedFuture$ else { fatalError("Upcall to apply unexpectedly returned a null future") }
        nonisolated(unsafe) let future$ = returnedFuture$
        _ = try! await _awaitCompletableFuture(future$)
        """,
        // A primitive result, read on the thread the task resumed on.
        "return Int64.fromJavaObject(result$?.javaThis, in: try! JavaVirtualMachine.shared().environment())",
      ]
    )
  }

  @Test
  func throwingClosurePropagatesTheJavaFailure() throws {
    try assertOutput(
      input: source,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "let returnedFuture$ = try javaInterface_fetch$call.dynamicJavaMethodCall(methodName: \"apply\", arguments: _0, resultType: JavaCompletableFuture?.self)",
        "let result$ = try await _awaitCompletableFuture(future$)",
        "let result$MemoryAddress$ = unwrapped$.as(JavaJNISwiftInstance.self)!.memoryAddress()",
      ]
    )
  }

  @Test
  func legacyFutureMode_isSkipped() throws {
    var config = Configuration()
    config.asyncFuncMode = .legacyFuture
    try assertOutput(
      input: "public func perform(_ work: @escaping @Sendable () async -> Void) async {}",
      config: config,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [],
      notExpectedChunks: ["perform("]
    )
  }

  /// `dynamicJavaMethodCall` takes `JavaValue`s: a `JavaOptional` argument is passed as an optional.
  @Test
  func optionalArgumentIsPassedAsAnOptional() throws {
    try assertOutput(
      input: "public func onSetIcon(_ set: @escaping (String?) async -> Void) {}",
      .jni,
      .swift,
      expectedChunks: [
        "arguments: Optional(_0.map {"
      ]
    )
  }
}
