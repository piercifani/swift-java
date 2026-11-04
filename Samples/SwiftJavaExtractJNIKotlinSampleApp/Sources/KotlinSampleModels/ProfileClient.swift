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

/// A protocol implemented in Kotlin and passed into Swift code in another module.
public struct Profile: Sendable {
  public var name: String

  public init(name: String) {
    self.name = name
  }
}

public enum ClientError: Error {
  case offline
}

public protocol ProfileClient: Sendable {
  func displayName(for id: String) -> String
  func profile(id: String) -> Profile
  /// Implemented in Kotlin by returning a `CompletableFuture`, which Swift awaits without blocking.
  func fetch(id: String) async throws -> Profile
}
