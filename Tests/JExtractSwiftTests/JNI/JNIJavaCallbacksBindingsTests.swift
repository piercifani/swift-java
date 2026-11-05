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

/// With `javaCallbacksBindings: jextract`, jextract prints the bindings Swift calls Java implementations of
/// protocols through, so the build runs no Java tools.
@Suite
struct JNIJavaCallbacksBindingsTests {
  func config(bindings: JExtractJavaCallbacksBindings?) -> Configuration {
    var config = Configuration()
    config.enableJavaCallbacks = true
    config.javaCallbacksBindings = bindings
    return config
  }

  let observerSource = """
    public struct Message {}
    public protocol Observer {
      func dispose()
      func name() -> String
      func send(_ message: Message)
    }
    public func observe(_ makeObserver: @escaping (String) -> any Observer) {}
    """

  @Test
  func jextractBindings_printTheJavaInterface() throws {
    try assertOutput(
      input: observerSource,
      config: config(bindings: .jextract),
      .jni,
      .swift,
      detectChunkByInitialLines: 2,
      expectedChunks: [
        """
        @JavaInterface("com.example.swift.Observer")
        public struct JavaObserver {
          @JavaMethod("dispose")
          public func dispose()

          @JavaMethod("name")
          public func name() -> String

          @JavaMethod("send")
          public func send(_ p0: JavaMessage?)
        }
        """,
        #"@JavaClass("com.example.swift.Message")"#,
      ]
    )
  }

  @Test
  func wrapJavaBindings_leaveTheJavaInterfaceToWrapJava() throws {
    try assertOutput(
      input: observerSource,
      config: config(bindings: nil),
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [],
      notExpectedChunks: [
        #"@JavaInterface("com.example.swift.Observer")"#
      ]
    )
  }

  @Test
  func closureReturningProtocol_acceptsJavaImplementations() throws {
    try assertOutput(
      input: observerSource,
      config: config(bindings: .jextract),
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "final class SwiftJavaObserverImplementation: SwiftJavaObserverWrapper, @unchecked Sendable {",
        "public func apply(_ _0: String) -> JavaObject!",
        "if let instance$ = unwrapped$.as(JavaJNISwiftInstance.self) {",
        "existential$ = SwiftJavaObserverImplementation(_javaObserverInterface: JavaObserver(javaThis: unwrapped$.javaThis, environment: unwrapped$.javaEnvironment))",
      ]
    )
    try assertOutput(
      input: observerSource,
      config: config(bindings: .jextract),
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "Observer apply(java.lang.String _0);"
      ]
    )
  }

  @Test
  func closureReturningProtocol_withoutCallbacksIsSkipped() throws {
    try assertOutput(
      input: observerSource,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [],
      notExpectedChunks: [
        "Java_com_example_swift_SwiftModule__00024observe"
      ]
    )
  }
}
