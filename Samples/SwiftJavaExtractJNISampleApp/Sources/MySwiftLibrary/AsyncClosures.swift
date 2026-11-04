//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift.org project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift.org project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// Async closures implemented in Java: Swift awaits the `CompletableFuture` they return.
public enum AsyncClosures {
  public static func perform(_ value: Int64, _ work: @escaping @Sendable (Int64) async -> Void) async {
    await work(value)
  }

  /// A non-escaping async closure.
  public static func addOne(_ value: Int64, _ f: (Int64) async -> Int64) async -> Int64 {
    await f(value) + 1
  }

  public static func capacity(_ fetch: @escaping @Sendable (Int64) async throws -> MySwiftStruct) async throws -> Int64 {
    try await fetch(7).getCapacity()
  }
}
