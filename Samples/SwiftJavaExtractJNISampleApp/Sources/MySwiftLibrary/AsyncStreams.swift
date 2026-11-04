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

/// `AsyncStream` results are returned to Java as a `SwiftAsyncStream`.
public func countdown(from start: Int64) -> AsyncStream<Int64> {
  AsyncStream { continuation in
    for value in stride(from: start, through: 0, by: -1) {
      continuation.yield(value)
    }
    continuation.finish()
  }
}

public func shapes(count: Int64) -> AsyncStream<Square> {
  AsyncStream { continuation in
    for side in 1...max(count, 1) {
      continuation.yield(Square(side: Double(side)))
    }
    continuation.finish()
  }
}
