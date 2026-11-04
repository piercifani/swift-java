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

import KotlinSampleModels

/// Uses a protocol declared in KotlinSampleModels, implemented in Kotlin.
public final class ProfileService: Sendable {
  let client: any ProfileClient

  public init(client: any ProfileClient) {
    self.client = client
  }

  public func title(id: String) -> String {
    client.displayName(for: id)
  }

  public func name(id: String) -> String {
    client.profile(id: id).name
  }

  public func load(id: String) async throws -> String {
    try await client.fetch(id: id).name
  }

  /// Starts a fetch, cancels it, and reports whether it ended without a value.
  public func fetchThenCancel(id: String) async -> Bool {
    let client = self.client
    let task = Task { try await client.fetch(id: id) }
    try? await Task.sleep(for: .milliseconds(50))
    task.cancel()
    return (try? await task.value) == nil
  }
}
