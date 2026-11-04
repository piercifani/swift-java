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

/// Cancelling the future returned for an exported `async` function cancels the Swift task.
@Suite
struct JNIAsyncCancellationTests {
  @Test
  func returnedFutureForwardsCancellation() throws {
    try assertOutput(
      input: "public func work() async -> Int64 { 0 }",
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "return org.swift.swiftkit.core.CompletableFutureCancellation.forwardCancellation(future$.thenApply((futureResult$) -> {",
        "), future$);",
      ]
    )
  }

  @Test
  func taskIsRegisteredWithTheFuture() throws {
    try assertOutput(
      input: "public func work() async -> Int64 { 0 }",
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        if let task {
          SwiftJavaRuntimeSupport._cancelTaskWhenFutureIsCancelled(result_future, task: task, environment: environment)
        }
        """
      ]
    )
  }

  @Test
  func legacyFutureModeIsUnchanged() throws {
    var config = Configuration()
    config.asyncFuncMode = .legacyFuture
    try assertOutput(
      input: "public func work() async -> Int64 { 0 }",
      config: config,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [],
      notExpectedChunks: ["_cancelTaskWhenFutureIsCancelled"]
    )
    try assertOutput(
      input: "public func work() async -> Int64 { 0 }",
      config: config,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [],
      notExpectedChunks: ["forwardCancellation"]
    )
  }
}
