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

/// Swift protocols implemented in Java: `async` requirements, and protocols from other modules.
@Suite
struct JNIJavaImplementedProtocolTests {
  var config: Configuration {
    var config = Configuration()
    config.enableJavaCallbacks = true
    return config
  }

  let asyncSource = """
    public struct Profile {}
    public protocol ProfileClient {
      func fetch(id: String) async throws -> Profile
      func count() async -> Int64
      func refresh() async
    }
    """

  @Test
  func asyncRequirement_awaitsTheReturnedFuture() throws {
    try assertOutput(
      input: asyncSource,
      config: config,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        public func fetch(id: String) async throws -> Profile {
          let environment$ = try! JavaVirtualMachine.shared().environment()
          let future$ = try environment$.withLocalFrame(capacity: 6) {
            let javaInterface$ = JavaProfileClient(javaThis: _javaProfileClientInterface.javaThis, environment: environment$)
            return try javaInterface$.dynamicJavaMethodCall(methodName: "fetch", arguments: id, Optional(JavaSwiftArena.defaultAutoArena), resultType: JavaCompletableFuture?.self)
          }
          guard let future$ else {
            fatalError("Upcall to fetch unexpectedly returned a null future")
          }
          let result$ = try await _awaitCompletableFuture(future$)
          let resumedEnvironment$ = try! JavaVirtualMachine.shared().environment()
        """
      ]
    )
  }

  @Test
  func asyncRequirement_unboxesPrimitivesAndHandlesVoid() throws {
    try assertOutput(
      input: asyncSource,
      config: config,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "return Int64.fromJavaObject(result$?.javaThis, in: resumedEnvironment$)",
        "_ = try! await _awaitCompletableFuture(future$)",
      ]
    )
  }

  /// A requirement Swift can't call on a Java implementation stops with an error, and doesn't keep Java
  /// from implementing the others.
  @Test
  func asyncRequirement_needsCompletableFutureMode() throws {
    var config = self.config
    config.asyncFuncMode = .legacyFuture
    try assertOutput(
      input: asyncSource,
      config: config,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public protocol SwiftJavaProfileClientWrapper",
        #"fatalError("ProfileClient.fetch can't be called on a Java implementation yet")"#,
      ]
    )
  }

  @Test
  func asyncRequirement_unsupportedResultStopsWithAnError() throws {
    try assertOutput(
      input: """
        public struct Profile {}
        public protocol ProfileClient {
          func fetchAll() async -> [Profile]
        }
        """,
      config: config,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public protocol SwiftJavaProfileClientWrapper",
        #"fatalError("ProfileClient.fetchAll can't be called on a Java implementation yet")"#,
      ]
    )
  }

  // MARK: Protocols from other modules

  let crossModuleSource = """
    import Core
    public func use(client: any ProfileClient) {}
    """
  let coreSource = """
    public protocol ProfileClient {
      func name() -> String
    }
    """

  @Test
  func crossModuleProtocol_acceptsJavaImplementations() throws {
    try assertOutput(
      input: crossModuleSource,
      config: config,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      dependencySwiftSources: ["Core": coreSource],
      moduleJavaPackages: ["Core": "com.example.core"],
      javaCallbackModules: ["Core"],
      expectedChunks: [
        "final class _SwiftModule_use_client_Wrapper: SwiftJavaProfileClientWrapper, @unchecked Sendable {",
        "if environment.interface.IsInstanceOf(environment, client, _JNIMethodIDCache.JNISwiftInstance.class) != 0 {",
        "clientswiftObject$ = _SwiftModule_use_client_Wrapper(_javaProfileClientInterface: JavaProfileClient(javaThis: client!, environment: environment))",
      ]
    )
  }

  @Test
  func crossModuleProtocol_withoutCallbacksOnlyAcceptsSwiftInstances() throws {
    try assertOutput(
      input: crossModuleSource,
      config: config,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      dependencySwiftSources: ["Core": coreSource],
      moduleJavaPackages: ["Core": "com.example.core"],
      expectedChunks: [],
      notExpectedChunks: [
        "_SwiftModule_use_client_Wrapper"
      ]
    )
  }

  @Test
  func crossModuleProtocol_genericBoundIsQualified() throws {
    try assertOutput(
      input: crossModuleSource,
      config: config,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      dependencySwiftSources: ["Core": coreSource],
      moduleJavaPackages: ["Core": "com.example.core"],
      expectedChunks: [
        "public static <_T0 extends com.example.core.ProfileClient> void use(_T0 client)"
      ]
    )
  }
}
