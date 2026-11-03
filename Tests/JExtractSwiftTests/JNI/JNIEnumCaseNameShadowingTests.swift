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

/// Inside the generated `Case` interface, each record name shadows a type with the same
/// simple name, so payload types with such a name must be fully qualified.
@Suite
struct JNIEnumCaseNameShadowingTests {
  @Test
  func caseNamedLikeItsPayload() throws {
    try assertOutput(
      input: """
        public struct Market {}
        public enum Destination {
          case home
          case market(Market)
        }
        """,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        public sealed interface Case {
          record Home() implements Case {}
          record Market(com.example.swift.Market arg0) implements Case {}
        }
        """
      ]
    )
  }

  @Test
  func anotherCasesRecordShadowsThePayload() throws {
    try assertOutput(
      input: """
        public struct Market {}
        public enum Feed {
          case market
          case featured(Market)
          case list([Market])
        }
        """,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        public sealed interface Case {
          record Market() implements Case {}
          record Featured(com.example.swift.Market arg0) implements Case {}
          record List(com.example.swift.Market[] arg0) implements Case {}
        }
        """
      ]
    )
  }

  @Test
  func unshadowedPayloadsStayUnqualified() throws {
    try assertOutput(
      input: """
        public struct Item {}
        public enum Route {
          case home
          case detail(Item)
        }
        """,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        public sealed interface Case {
          record Home() implements Case {}
          record Detail(Item arg0) implements Case {}
        }
        """
      ]
    )
  }
}
