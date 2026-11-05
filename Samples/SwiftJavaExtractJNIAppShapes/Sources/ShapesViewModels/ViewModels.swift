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
import ShapesClients
import ShapesDependencies
import ShapesModels
import ShapesUtil
import SwiftJavaAnnotations

/// Shape: a main-actor `@Observable` view model whose callbacks Kotlin implements.
@JavaExport
@MainActor
@Observable
public final class LoginViewModel {
  /// Shape: callbacks typed with another module's `@MainActor` typealias, with defaults.
  @JavaExport
  public struct Callbacks: @unchecked Sendable {
    @JavaExport(false)
    public let didLogin: VoidCallback
    @JavaExport(false)
    public let didCancel: VoidCallback

    public init(didLogin: @escaping VoidCallback = {}, didCancel: @escaping VoidCallback = {}) {
      self.didLogin = didLogin
      self.didCancel = didCancel
    }
  }

  @ObservationIgnored private let callbacks: Callbacks
  public private(set) var email = ""

  public init(callbacks: Callbacks) {
    self.callbacks = callbacks
  }

  public func submit(email: String) {
    self.email = email
    email.isEmpty ? callbacks.didCancel() : callbacks.didLogin()
  }
}

/// Shape: a main-actor `@Observable` view model with async loading and many kinds of callbacks.
@JavaExport
@MainActor
@Observable
public final class ShelfViewModel {
  @JavaExport
  public struct Callbacks: @unchecked Sendable {
    @JavaExport(false) public let onOpen: @MainActor (Book) -> Void
    @JavaExport(false) public let onSelect: @MainActor ([Book]) -> Void
    @JavaExport(false) public let onShareLinks: @MainActor ([URL]) -> Void
    @JavaExport(false) public let onVerify: @MainActor (String?, Int64?) -> Void
    @JavaExport(false) public let onShare: @MainActor (ShelfViewModel, Genre) async -> Void
    @JavaExport(false) public let onSetIcon: @MainActor (String?) async -> Void

    public init(
      onOpen: @escaping @MainActor (Book) -> Void = { _ in },
      onSelect: @escaping @MainActor ([Book]) -> Void = { _ in },
      onShareLinks: @escaping @MainActor ([URL]) -> Void = { _ in },
      onVerify: @escaping @MainActor (String?, Int64?) -> Void = { _, _ in },
      onShare: @escaping @MainActor (ShelfViewModel, Genre) async -> Void = { _, _ in },
      onSetIcon: @escaping @MainActor (String?) async -> Void = { _ in }
    ) {
      self.onOpen = onOpen
      self.onSelect = onSelect
      self.onShareLinks = onShareLinks
      self.onVerify = onVerify
      self.onShare = onShare
      self.onSetIcon = onSetIcon
    }
  }

  @ObservationIgnored private let dependencies: Dependencies
  @ObservationIgnored private let callbacks: Callbacks
  public private(set) var books: [Book] = []
  public private(set) var isLoading = false

  public init(dependencies: Dependencies, callbacks: Callbacks) {
    self.dependencies = dependencies
    self.callbacks = callbacks
  }

  public var appName: String { dependencies.system.appName() }

  public func load(query: String) async throws {
    isLoading = true
    defer { isLoading = false }
    books = try await dependencies.clients.search.search(query: query)
  }

  public func open(index: Int64) {
    callbacks.onOpen(books[Int(index)])
  }

  public func selectAll() {
    callbacks.onSelect(books)
    callbacks.onShareLinks(books.compactMap(\.coverURL))
  }

  public func verify(code: String?, attempt: Int64?) {
    callbacks.onVerify(code, attempt)
  }

  public func share(genre: Genre) async {
    await callbacks.onShare(self, genre)
  }

  public func setIcon(_ name: String?) async {
    await callbacks.onSetIcon(name)
  }

  /// Shape: a seed provider returning an optional array of entities.
  /// Gap: closures taking or returning optional arrays aren't supported yet.
  @JavaExport(false)
  public func setSeedProvider(_ provider: @escaping (String) -> [Book]?) {}

  #if os(Android)
  /// Shape: Android-only API on a view model.
  /// Gap: see `Platform.androidOnly()`.
  @JavaExport(false)
  public func androidBackPressed() {}
  #endif
}

/// For the tests: runs the main run loop briefly, as Android's main looper would, so main-actor work
/// scheduled by async calls can run while the JVM main thread waits.
@JavaExport
public enum MainLoop {
  @MainActor
  public static func run(seconds: Double) {
    _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: seconds))
  }
}
