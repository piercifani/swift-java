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

/// Members implemented in a protocol extension are `default` methods of the Java interface.
@Suite
struct JNIProtocolExtensionTests {
  let source =
    """
    public protocol Scene {
      var id: String { get }
      var title: String { get }
    }

    extension Scene {
      public var title: String { "" }
      public func uid() -> String { id }
    }

    public struct DefaultScene: Scene {
      public let id: String
    }
    """

  @Test
  func interface_javaBindings() throws {
    try assertOutput(
      input: source,
      .jni,
      .java,
      expectedChunks: [
        "public java.lang.String getId();",
        "public default java.lang.String getTitle() {",
        "return SceneBox.$getTitle(this.$memoryAddress(), this.$typeMetadataAddress());",
        "public default java.lang.String uid() {",
        "return SceneBox.$uid(this.$memoryAddress(), this.$typeMetadataAddress());",
        "static native java.lang.String $uid(long selfPointer, long selfTypePointer);",
      ],
      notExpectedChunks: [
        "public java.lang.String getTitle();",
        "public java.lang.String uid();",
        "private static native java.lang.String $uid(long selfPointer, long selfTypePointer);",
      ]
    )
  }
}
