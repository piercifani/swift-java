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

/// Closures returned to Java, and an optional closure property.
public final class ClosureFactory {
  public var onStruct: ((MySwiftStruct) -> Void)?

  public init() {}

  public func makeAdder(_ base: Int64) -> (Int64) -> Int64 {
    { base + $0 }
  }

  public func makeDescriber() -> (MySwiftStruct, String) -> String {
    { "\($1)\($0.getCapacity())" }
  }

  public func send(_ value: MySwiftStruct) {
    onStruct?(value)
  }

  /// How many closures from `makeTracked()` were released.
  nonisolated(unsafe) public static var releasedClosures: Int64 = 0

  /// A closure holding an object that counts its release.
  public static func makeTracked() -> () -> Int64 {
    let tracker = ReleaseTracker()
    return { tracker.value }
  }
}

final class ReleaseTracker {
  let value: Int64 = 1

  deinit {
    ClosureFactory.releasedClosures += 1
  }
}
