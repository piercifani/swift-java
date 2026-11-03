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


/// `async` requirements implemented in Java return a `CompletableFuture`, which Swift awaits.
public protocol AsyncCallbackProtocol {
  func fetchValue(_ input: Int64) async -> Int64
  func fetchObject(_ input: Int64) async throws -> MySwiftClass
}

public func callAsyncCallbacks(_ callbacks: some AsyncCallbackProtocol, input: Int64) async throws -> Int64 {
  let value = await callbacks.fetchValue(input)
  let object = try await callbacks.fetchObject(input)
  return value + object.x
}
