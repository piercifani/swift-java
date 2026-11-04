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

/// A conformer's method with a closure parameter takes the protocol's functional interface, so it
/// overrides the interface method.
@Suite
struct JNIProtocolClosureParameterTests {
  let source =
    """
    public protocol Tracker {
      func onEvent(_ handler: @escaping (Int64, Int64) -> Void)
    }

    public final class TrackerMock: Tracker {
      public func onEvent(_ handler: @escaping (Int64, Int64) -> Void) {}
    }
    """

  @Test
  func conformer_javaBindings() throws {
    try assertOutput(
      input: source,
      .jni,
      .java,
      expectedChunks: [
        "public void onEvent(com.example.swift.Tracker.onEvent.handler handler);",
        "public void onEvent(com.example.swift.Tracker.onEvent.handler handler) {",
        "private static native void $onEvent(com.example.swift.Tracker.onEvent.handler handler, long selfPointer);",
      ],
      notExpectedChunks: [
        "com.example.swift.TrackerMock.onEvent.handler handler"
      ]
    )
  }

  @Test
  func conformer_swiftThunks() throws {
    try assertOutput(
      input: source,
      .jni,
      .swift,
      expectedChunks: [
        #"@JavaInterface("com.example.swift.Tracker$onEvent$handler")"#,
        "public struct JavaTrackerMock_onEvent_handler",
        // The existential box's dispatch thunk wraps the closure too.
        "public struct JavaTracker_onEvent_handler",
      ]
    )
  }
}
