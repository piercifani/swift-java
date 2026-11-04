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

@Suite
struct JNINameCollisionTests {
  let source =
    """
    public struct Standard {}
    public struct Sports {}

    public struct Market {
      public init(standard: Standard) {}
      public init(sports: Sports) {}
    }
    """

  @Test
  func overloadsLoweringToTheSameNativeSignature_javaBindings() throws {
    try assertOutput(
      input: source,
      .jni,
      .java,
      expectedChunks: [
        "return Market.wrapMemoryAddressUnsafe(Market.$init(standard.$memoryAddress()), swiftArena);",
        "private static native long $init(long standard);",
        "return Market.wrapMemoryAddressUnsafe(Market.$init$1(sports.$memoryAddress()), swiftArena);",
        "private static native long $init$1(long sports);",
      ]
    )
  }

  @Test
  func overloadsLoweringToTheSameNativeSignature_swiftThunks() throws {
    try assertOutput(
      input: source,
      .jni,
      .swift,
      expectedChunks: [
        "func Java_com_example_swift_Market__00024init__J(environment: UnsafeMutablePointer<JNIEnv?>!, thisClass: jclass, standard: jlong) -> jlong {",
        "func Java_com_example_swift_Market__00024init_000241__J(environment: UnsafeMutablePointer<JNIEnv?>!, thisClass: jclass, sports: jlong) -> jlong {",
      ]
    )
  }

  @Test
  func accessorsWithTheSameJavaName_javaBindings() throws {
    try assertOutput(
      input: """
        public struct EventState {
          public let live: Bool
          public var isLive: Bool { live }
          public var title: String
          public static var title: String { "" }
        }
        """,
      .jni,
      .java,
      expectedChunks: [
        "public boolean getLive() {",
        "public boolean isLive() {",
        "public java.lang.String getTitle() {",
        "public static java.lang.String getTitle_() {",
        "public void setTitle(java.lang.String newValue) {",
      ]
    )
  }

  @Test
  func accessorsWithTheSameJavaName_swiftThunks() throws {
    try assertOutput(
      input: """
        public struct EventState {
          public let live: Bool
          public var isLive: Bool { live }
        }
        """,
      .jni,
      .swift,
      expectedChunks: [
        "func Java_com_example_swift_EventState__00024getLive__J(",
        "func Java_com_example_swift_EventState__00024isLive__J(",
      ]
    )
  }
}
