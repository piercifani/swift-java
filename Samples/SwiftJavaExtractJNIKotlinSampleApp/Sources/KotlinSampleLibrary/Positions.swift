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

/// Swift names that are Java keywords: `long`, `short`, `default`, and a method named `wait`.
public struct Position: Sendable {
  public static let `default`: Position = Position(size: 0, long: true)

  public var size: Int64
  public var isLong: Bool

  public init(size: Int64, long: Bool) {
    self.size = size
    self.isLong = long
  }

  public func label(long: String, short: String) -> String {
    isLong ? long : short
  }

  public func wait() -> Int64 {
    size
  }
}

public enum Exposure {
  case split(long: Int64, short: Int64)
}
