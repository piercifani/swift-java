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

import Foundation
import Observation

/// The shape of a Skip Fuse view model: a main-actor, observable open base class; a subclass with
/// callbacks taking structs, an input enum with payloads, and async loading.
@MainActor
@Observable
open class BaseViewModel {
  public var isLoading = false

  public init() {}

  open func setup() {}
}

@MainActor
public final class MarketViewModel: BaseViewModel {
  public struct Callbacks: Sendable {
    let onOpen: @MainActor @Sendable (Market) -> Void
    let onClose: @MainActor @Sendable () -> Void

    public init(
      onOpen: @escaping @MainActor @Sendable (Market) -> Void,
      onClose: @escaping @MainActor @Sendable () -> Void
    ) {
      self.onOpen = onOpen
      self.onClose = onClose
    }
  }

  public enum Input: Sendable {
    case tapped(Market)
    case closeTapped
  }

  public private(set) var markets: [Market] = []
  private let callbacks: Callbacks

  public init(callbacks: Callbacks) {
    self.callbacks = callbacks
    super.init()
  }

  public override func setup() {
    markets = [Market(id: "1")]
  }

  public func send(_ input: Input) {
    switch input {
    case .tapped(let market): callbacks.onOpen(market)
    case .closeTapped: callbacks.onClose()
    }
  }

  public func load() async {
    isLoading = true
    markets = [Market(id: "1"), Market(id: "2")]
    isLoading = false
  }
}

/// For the tests: runs the main run loop briefly, which drains the main queue as Android's main
/// looper does, so main-actor work can run while the JVM main thread waits.
public enum MainLoop {
  @MainActor
  public static func run(seconds: Double) {
    _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: seconds))
  }
}
