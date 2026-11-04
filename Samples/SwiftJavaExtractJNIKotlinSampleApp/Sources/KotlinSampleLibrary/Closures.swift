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

import Dispatch

/// Escaping closures whose parameters are jextracted types, optionals of them, and closure types
/// carrying @Sendable or @MainActor.
public final class Notifier {
  private var handler: ((Item) -> Void)?

  /// An optional closure property: a Kotlin property of the setter's functional interface.
  public var onItem: ((Item) -> Void)?

  public init() {}

  public func emit(id: String) {
    onItem?(Item(id: id, count: 1))
  }

  /// A closure returned to Kotlin.
  public func makeFormatter(prefix: String) -> (Item) -> String {
    { "\(prefix)\($0.id)" }
  }

  public func setHandler(_ handler: @escaping (Item) -> Void) {
    self.handler = handler
  }

  public func fire(id: String) {
    handler?(Item(id: id, count: 1))
  }

  /// Mixed arity with an optional struct parameter.
  public func check(_ cb: @escaping (String, Int64, Item?) -> Bool) -> Bool {
    cb("a", 1, nil) && cb("b", 2, Item(id: "b", count: 2))
  }

  /// A non-escaping closure taking and returning a struct.
  public func transform(id: String, _ f: (Item) -> Item) -> Item {
    f(Item(id: id, count: 1))
  }

  /// An async closure: Swift awaits the future the Kotlin lambda returns.
  public func perform(id: String, _ work: @escaping @Sendable (Item) async -> Void) async {
    await work(Item(id: id, count: 1))
  }

  /// A @Sendable closure called on another thread: the upcall uses that thread's JNIEnv.
  public func deliverInBackground(id: String, _ cb: @escaping @Sendable (Item) -> Void) {
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
      cb(Item(id: id, count: 1))
      group.leave()
    }
    group.wait()
  }
}

/// The shape of a view model's callbacks: @MainActor @Sendable closures taking structs.
public struct Callbacks: Sendable {
  let onOpen: @MainActor @Sendable (Item) -> Void
  let onClose: @MainActor @Sendable () -> Void

  public init(
    onOpen: @escaping @MainActor @Sendable (Item) -> Void,
    onClose: @escaping @MainActor @Sendable () -> Void
  ) {
    self.onOpen = onOpen
    self.onClose = onClose
  }
}

@MainActor
public enum Screen {
  public static func open(_ callbacks: Callbacks, id: String) {
    callbacks.onOpen(Item(id: id, count: 1))
    callbacks.onClose()
  }
}
