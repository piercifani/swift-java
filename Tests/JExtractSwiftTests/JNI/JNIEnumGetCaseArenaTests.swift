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

/// `getCase()` on an enum with payloads gets an arena-free overload when a global automatic arena exists.
@Suite
struct JNIEnumGetCaseArenaTests {
  let source = """
    public struct Item {}
    public enum Route {
      case home
      case detail(Item)
    }
    """

  @Test
  func allowGlobalAutomatic_hasArenaFreeGetCase() throws {
    var config = Configuration()
    config.memoryManagementMode = .allowGlobalAutomatic
    try assertOutput(
      input: source,
      config: config,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public Case getCase(SwiftArena swiftArena) {",
        """
        public Case getCase() {
          return getCase(SwiftMemoryManagement.DEFAULT_SWIFT_JAVA_AUTO_ARENA);
        }
        """,
      ]
    )
  }

  @Test
  func explicitMode_onlyHasGetCaseWithArena() throws {
    try assertOutput(
      input: source,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: ["public Case getCase(SwiftArena swiftArena) {"],
      notExpectedChunks: ["public Case getCase() {"]
    )
  }
}
