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

/// View models are main-actor isolated. Their Java bindings stay synchronous and must be called
/// on the main thread (Compose's UI thread on Android).
@MainActor
public final class CounterViewModel {
  public private(set) var count: Int64 = 0
  public var title: String

  public init(title: String) {
    self.title = title
  }

  public func increment() {
    count += 1
  }
}
