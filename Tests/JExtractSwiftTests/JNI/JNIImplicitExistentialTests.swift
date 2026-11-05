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

/// A protocol used as a type without `any` (allowed in Swift 5 mode) is an existential, like `any P`.
@Suite
struct JNIImplicitExistentialTests {
  let source =
    """
    public protocol Client {
      func ping() -> Int
    }

    public struct Clients {
      public let client: Client
      public init(client: Client) { self.client = client }
      public func use(client: Client) {}
    }
    """

  @Test
  func bareProtocol_javaBindings() throws {
    try assertOutput(
      input: source,
      .jni,
      .java,
      expectedChunks: [
        "public Client getClient(SwiftArena swiftArena) {",
        "return ClientBox.wrapMemoryAddressUnsafe(result.selfPointer, result.selfTypePointer, swiftArena);",
        "public static <_T0 extends Client> Clients init(_T0 client, SwiftArena swiftArena) {",
        "private static native long $init(java.lang.Object client);",
        "public <_T0 extends Client> void use(_T0 client) {",
        "private static native void $use(java.lang.Object client, long selfPointer);",
      ],
      notExpectedChunks: [
        "Client.wrapMemoryAddressUnsafe("
      ]
    )
  }

  @Test
  func boxIsPublicForOtherModules_javaBindings() throws {
    try assertOutput(
      input: source,
      .jni,
      .java,
      expectedChunks: [
        "public final class ClientBox implements JNISwiftInstance, Client {"
      ]
    )
  }
}
