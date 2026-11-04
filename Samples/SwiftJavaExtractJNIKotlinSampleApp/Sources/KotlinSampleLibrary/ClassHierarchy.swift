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

/// Swift subclasses become Kotlin-visible subclasses.
open class Animal {
  public let name: String

  public init(name: String) {
    self.name = name
  }

  open func sound() -> String { "..." }

  public func describe() -> String { "\(name) says \(sound())" }
}

public final class Dog: Animal {
  public override init(name: String) {
    super.init(name: name)
  }

  public override func sound() -> String { "woof" }

  public func fetch() -> String { "stick" }
}

public enum Zoo {
  public static func describe(_ animal: Animal) -> String { animal.describe() }

  /// Returned as `Animal`; Kotlin receives a `Dog`.
  public static func makeDog(name: String) -> Animal { Dog(name: name) }
}
