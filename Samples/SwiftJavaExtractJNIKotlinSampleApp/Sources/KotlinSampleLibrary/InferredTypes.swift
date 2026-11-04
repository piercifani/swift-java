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

/// Closures over platform-width `Int` get their own functional interface.
public enum Arithmetic {
  public static func apply(_ f: (Int) -> Int, to x: Int) -> Int {
    f(x)
  }

  public static func combine(_ a: Int, _ b: Int, _ f: (Int, Int) -> Int) -> Int {
    f(a, b)
  }
}

/// Properties without a type annotation: the type is inferred from a literal or an initializer call.
public final class Settings {
  public static let maximumCount = 42
  public var isEnabled = false
  public var title = "Untitled"
  public var ratio = 0.5
  public var featured = Item(id: "featured", count: 0)

  public init() {}
}
