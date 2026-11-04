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

/// Arrays whose elements are optionals or dictionaries.
public enum Watchlist {
  /// A row per symbol; a symbol without a quote yet is `nil`.
  public static func quotes() -> [Item?] {
    [Item(id: "a", count: 1), nil, Item(id: "c", count: 3)]
  }

  /// Positions per page.
  public static func pages() -> [[String: Int64]] {
    [["a": 1], ["b": 2, "c": 3]]
  }

  public static func total(counts: [Int64?]) -> Int64 {
    counts.compactMap { $0 }.reduce(0, +)
  }
}
