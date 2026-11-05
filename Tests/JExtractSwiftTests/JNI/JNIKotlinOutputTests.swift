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

/// `kotlinOutput`: Java shaped for Kotlin, and a Kotlin file per module on top of it.
@Suite
struct JNIKotlinOutputTests {
  var config: Configuration {
    var config = Configuration()
    config.kotlinOutput = true
    return config
  }

  @Test
  func closureOptionalParameters_areNullable() throws {
    let input = """
      public struct Item {}
      public func onVerify(_ cb: @escaping (String?, Int64?, Item?) -> Void) {}
      """
    try assertOutput(
      input: input,
      config: config,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: ["void apply(String _0, java.lang.Long _1, Item _2);"]
    )
    try assertOutput(
      input: input,
      config: config,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public func apply(_ _0: JavaString?, _ _1: JavaLong?, _ _2: JavaItem?)",
        "return try! JavaClass<JavaLong>(environment: JavaVirtualMachine.shared().environment()).valueOf($0)",
      ]
    )
  }

  @Test
  func asyncFunctions_areSuspendFunctions() throws {
    try assertOutput(
      input: """
        public struct Item {}
        public final class Store {
          public func load(id: String) async throws -> Item { Item() }
          public func reset() async {}
        }
        """,
      config: config,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public java.util.concurrent.CompletableFuture<Item> loadAsync(java.lang.String id, SwiftArena swiftArena)",
        // Without a global arena, the result's arena is a parameter.
        """
        suspend fun Store.load(id: String, swiftArena: org.swift.swiftkit.core.SwiftArena): Item =
          loadAsync(id, swiftArena).await()
        """,
        """
        suspend fun Store.reset(): Unit {
          resetAsync().await()
        }
        """,
      ]
    )
  }

  @Test
  func enumPayloads_areNullable() throws {
    try assertOutput(
      input: """
        public enum Message {
          case string(String)
          case closed(code: Int64, reason: String?)
        }
        """,
      config: config,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "record Closed(long code, java.lang.String reason) implements Case {}",
        "(t.$1.isPresent() ? t.$1.get() : null)",
      ]
    )
  }

  @Test
  func asyncStreams_areFlows() throws {
    try assertOutput(
      input: """
        public final class Progress {
          public func updates() -> AsyncStream<Double> { AsyncStream { _ in } }
        }
        """,
      config: config,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public org.swift.swiftkit.core.SwiftAsyncStream<java.lang.Double> updatesStream()",
        """
        fun Progress.updates(): kotlinx.coroutines.flow.Flow<Double> =
          updatesStream().asFlow()
        """,
        "private fun <T> org.swift.swiftkit.core.SwiftAsyncStream<T>.asFlow(): kotlinx.coroutines.flow.Flow<T> =",
      ]
    )
  }

  @Test
  func extensionOfDependencyType_isAnExtensionFunction() throws {
    var config = self.config
    config.swiftModule = "PrimaryLib"
    try assertOutput(
      input: """
        import DependencyLib
        extension Payload {
          public func doubled() -> Int32 { value * 2 }
        }
        """,
      config: config,
      .jni,
      .java,
      swiftModuleName: "PrimaryLib",
      detectChunkByInitialLines: 1,
      dependencySwiftSources: ["DependencyLib": "public struct Payload { public let value: Int32 }"],
      moduleJavaPackages: ["DependencyLib": "com.example.dep"],
      expectedChunks: [
        """
        fun com.example.dep.Payload.doubled(): Int =
          Payload.wrapMemoryAddressUnsafe(`$memoryAddress`(), BorrowingArena).doubled()
        """
      ]
    )
  }

  @Test
  func asyncClosures_areImplementedWithSuspending() throws {
    try assertOutput(
      input: "public func onShare(_ cb: @escaping (String) async -> Void) {}",
      config: config,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "fun suspending(block: suspend kotlinx.coroutines.CoroutineScope.() -> Unit): java.util.concurrent.CompletableFuture<Void?> ="
      ]
    )
  }

  @Test
  func javaOutputIsUnchangedByDefault() throws {
    try assertOutput(
      input: "public final class Store { public func reset() async {} }",
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: ["public java.util.concurrent.CompletableFuture<java.lang.Void> reset()"],
      notExpectedChunks: ["resetAsync", "suspend fun"]
    )
  }
}
