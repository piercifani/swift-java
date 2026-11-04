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

/// Optionals are nullable in Kotlin (`optionalsAsNullable`).
public struct Quote: Sendable {
  public var symbol: String
  public var price: Double?
  public var note: String?

  public init(symbol: String, price: Double? = nil, note: String? = nil) {
    self.symbol = symbol
    self.price = price
    self.note = note
  }
}

public enum Quotes {
  public static func last(_ symbol: String) -> Quote? {
    symbol.isEmpty ? nil : Quote(symbol: symbol, price: 1.5)
  }

  public static func volume(_ symbol: String) -> Int64? {
    symbol == "a" ? 10 : nil
  }

  public static func describe(_ price: Double?, _ count: Int64?) -> String {
    "\(price.map { "\($0)" } ?? "-") \(count.map { "\($0)" } ?? "-")"
  }

  public static func invert(_ flag: Bool?) -> Bool? {
    flag.map { !$0 }
  }
}
