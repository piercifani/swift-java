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

/// A class with a shared instance: every Kotlin wrapper of it is equal.
public final class Session: Sendable {
  public static let shared: Session = Session(name: "shared")

  public let name: String

  public init(name: String) {
    self.name = name
  }

  public static func echo(_ session: Session) -> Session { session }
}

public enum Echo {
  /// Returns the same instance through its superclass type.
  public static func animal(_ animal: Animal) -> Animal { animal }
}
