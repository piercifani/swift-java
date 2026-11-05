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
import ShapesClients
import ShapesModels
import ShapesUtil
import SwiftJavaAnnotations

// exportMode "all".

/// Shape: a container of clients, typed as another module's protocols without `any`.
public struct Clients: Sendable {
  public let search: SearchClient
  public let notifications: NotificationsClient
  public let catalog: CatalogClient

  public init(search: SearchClient, notifications: NotificationsClient, catalog: CatalogClient) {
    self.search = search
    self.notifications = notifications
    self.catalog = catalog
  }
}

/// Shape: configuration read lazily through `@autoclosure` closures, one returning another module's enum.
public struct System: @unchecked Sendable {
  public let scheme: () -> Scheme
  public let appName: () -> String

  public init(scheme: @autoclosure @escaping () -> Scheme, appName: @autoclosure @escaping () -> String) {
    self.scheme = scheme
    self.appName = appName
  }
}

/// Shape: a generic wrapper for persisted values.
/// Gap: generic classes used with type arguments (`StateValue<Int64>`) aren't supported yet.
@JavaExport(false)
public final class StateValue<Value: Sendable>: @unchecked Sendable {
  public var value: Value

  public init(_ value: Value) {
    self.value = value
  }
}

/// Shape: app state with values Java reads, and one it doesn't.
public final class AppState: @unchecked Sendable {
  @JavaExport(false)
  public let launchCount = StateValue<Int64>(0)
  public private(set) var shelves: [ShelfID: Shelf] = [:]
  public private(set) var reader: Reader?

  public init() {}

  public func load(from catalog: CatalogClient) {
    shelves = catalog.all()
  }

  /// Shape: an async function taking an optional entity.
  public func connect(reader: Reader?) async {
    self.reader = reader
  }

  /// Shape: an async throwing function taking an entity.
  public func borrow(_ book: Book) async throws -> Loan {
    guard reader != nil else {
      throw LibraryError.offline
    }
    return Loan(book: book, days: 14)
  }
}

public struct Reader: Sendable {
  public let name: String

  public init(name: String) {
    self.name = name
  }
}

public struct Loan: Sendable {
  public let book: Book
  public let days: Int64

  public init(book: Book, days: Int64) {
    self.book = book
    self.days = days
  }
}

/// Shape: the dependencies a view model reads.
public struct Dependencies: Sendable {
  public let clients: Clients
  public let system: System
  public let state: AppState

  public init(clients: Clients, system: System, state: AppState) {
    self.clients = clients
    self.system = system
    self.state = state
  }

  /// The dependencies the tests use: in-memory clients over a small catalog.
  public static func preview() -> Dependencies {
    let books = [
      Book(id: "1", title: "A Short History", pages: 120, genre: .history),
      Book(id: "2", title: "Cosmos", pages: 300, genre: .science),
      Book(id: "3", title: "A Long Story", pages: 450, genre: .fiction),
    ]
    let shelf = Shelf(id: ShelfID("main"), books: books, tags: ["new"])
    return Dependencies(
      clients: Clients(
        search: SearchClientMock(id: "mock", books: books),
        notifications: NotificationsClientMock(),
        catalog: CatalogClient(shelves: [shelf])
      ),
      system: System(scheme: .debug, appName: "Library"),
      state: AppState()
    )
  }
}
