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

/// An enum case's unlabeled closure payload: its interface is named like the Java parameter.
@Suite
struct JNIUnnamedClosureParameterTests {
  @Test
  func enumCaseClosurePayload_javaBindings() throws {
    try assertOutput(
      input: """
        public enum Policy {
          case custom((Int64, Int64) -> Void)
        }
        """,
      .jni,
      .java,
      expectedChunks: [
        "public interface arg0 {",
        "public static Policy custom(com.example.swift.Policy.custom.arg0 arg0, SwiftArena swiftArena) {",
      ],
      notExpectedChunks: [
        "public interface _0 {"
      ]
    )
  }
}
