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

public enum Receipts {
  /// Defaults the Kotlin caller can leave out, as it would with a Kotlin default.
  public static func format(_ amount: Int64, currency: String = "USD", showsSign: Bool = false) -> String {
    "\(showsSign && amount > 0 ? "+" : "")\(amount) \(currency)"
  }
}

/// Callbacks with defaults, like a view model's: Kotlin passes both or neither.
public struct ReceiptPrinter: Sendable {
  private let onPrinted: @Sendable (String) -> Void
  private let onFailed: @Sendable () -> Void

  public init(
    onPrinted: @escaping @Sendable (String) -> Void = { _ in },
    onFailed: @escaping @Sendable () -> Void = {}
  ) {
    self.onPrinted = onPrinted
    self.onFailed = onFailed
  }

  public func print(_ amount: Int64) {
    if amount >= 0 {
      onPrinted(Receipts.format(amount))
    } else {
      onFailed()
    }
  }
}
