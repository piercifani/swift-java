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

import SwiftJava

/// A public type whose Swift-only helpers stay out of the Kotlin API. Without `@JavaExport(false)`,
/// the tuple and `Any` members would be skipped declarations and fail this sample's build.
public struct SessionInfo {
  public var userName: String

  public init(userName: String) {
    self.userName = userName
  }

  @JavaExport(false)
  public func debugPairs() -> [(Int64, String)] {
    [(1, userName)]
  }

  /// Prefix operators have no Java mapping and are left out.
  public prefix static func - (info: SessionInfo) -> SessionInfo {
    SessionInfo(userName: String(info.userName.reversed()))
  }
}

@JavaExport(false)
extension SessionInfo {
  public var debugDump: [String: Any] {
    ["userName": userName]
  }
}
