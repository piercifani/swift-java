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
import Synchronization

/// A view model's stream of updates, collected in Kotlin as a Flow.
public final class PriceFeed: Sendable {
  private let stopped = Mutex(false)

  public init() {}

  /// A fixed series of prices.
  public func prices(count: Int64) -> AsyncStream<Item> {
    AsyncStream { continuation in
      for i in 0..<count {
        continuation.yield(Item(id: "price-\(i)", count: i))
      }
      continuation.finish()
    }
  }

  /// Prices until the connection drops: the stream then fails with `ClientError.offline`.
  public func pricesUntilOffline(count: Int64) -> AsyncThrowingStream<Item, Error> {
    AsyncThrowingStream { continuation in
      for i in 0..<count {
        continuation.yield(Item(id: "price-\(i)", count: i))
      }
      continuation.finish(throwing: ClientError.offline)
    }
  }

  /// Live updates that never finish on their own.
  public func live() -> AsyncStream<String> {
    AsyncStream { continuation in
      let task = Task {
        var i = 0
        while !Task.isCancelled {
          continuation.yield("update \(i)")
          i += 1
          try? await Task.sleep(for: .milliseconds(10))
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in
        task.cancel()
        self.stopped.withLock { $0 = true }
      }
    }
  }

  public func wasStopped() -> Bool {
    stopped.withLock { $0 }
  }
}
