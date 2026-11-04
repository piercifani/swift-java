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

import Synchronization

/// Long-running async work: cancelling the Kotlin coroutine awaiting it cancels the Swift task.
public final class Download: Sendable {
  private let cancelled = Mutex(false)

  public init() {}

  public func run() async -> Bool {
    do {
      try await Task.sleep(for: .seconds(30))
      return false
    } catch {
      cancelled.withLock { $0 = true }
      return true
    }
  }

  public func wasCancelled() -> Bool {
    cancelled.withLock { $0 }
  }
}
