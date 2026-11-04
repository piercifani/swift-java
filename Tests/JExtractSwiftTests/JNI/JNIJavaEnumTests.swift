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

/// With `payloadlessEnumsAsJavaEnums`, enums without associated values become Java `enum`s.
@Suite
struct JNIJavaEnumTests {
  var config: Configuration {
    var config = Configuration()
    config.payloadlessEnumsAsJavaEnums = true
    return config
  }

  let source = """
    public enum Phase {
      case idle
      case loading
    }
    """

  @Test
  func javaKeywordCaseIsEscaped() throws {
    try assertOutput(
      input: """
        public enum Policy {
          case `default`
          case strict
        }
        """,
      config: config,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: ["default_, strict;"]
    )
  }

  @Test
  func casesBecomeConstants() throws {
    try assertOutput(
      input: source,
      config: config,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public enum Phase implements JNISwiftInstance {",
        // Swift case names, as Swift and Kotlin code spell them.
        "idle, loading;",
        "static final long[] ADDRESSES = { Phase.$idle(), Phase.$loading() };",
        """
        public static Phase wrapMemoryAddressUnsafe(long selfPointer) {
          long typeMetadataAddress = Phase.$typeMetadataAddressDowncall();
          Phase value = values()[SwiftObjects.getRawDiscriminator(selfPointer, typeMetadataAddress)];
          SwiftObjects.destroy(selfPointer, typeMetadataAddress);
          return value;
        }
        """,
        """
        public long $memoryAddress() {
          return $SwiftValues.ADDRESSES[ordinal()];
        }
        """,
      ],
      notExpectedChunks: [
        "public boolean equals(Object obj)",
        "public int hashCode()",
        "private Phase(long selfPointer",
      ]
    )
  }

  @Test
  func classesWithoutTheOption() throws {
    try assertOutput(
      input: source,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: ["public final class Phase implements JNISwiftInstance {"]
    )
  }

  @Test(arguments: [
    "public enum Phase { case idle; case failed(String) }",
    "public enum Phase: Error { case idle }",
    "public enum Phase {}",
  ])
  func otherEnumsStayClasses(input: String) throws {
    try assertOutput(
      input: input,
      config: config,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: ["class Phase"],
      notExpectedChunks: ["enum Phase implements"]
    )
  }
}
