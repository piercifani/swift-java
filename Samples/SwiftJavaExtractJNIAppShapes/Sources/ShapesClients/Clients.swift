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
import ShapesModels
import ShapesUtil
import SwiftJavaAnnotations

// Combine on Apple platforms; elsewhere an implementation of the same API (such as OpenCombine).
#if canImport(Combine)
import Combine
#elseif canImport(OpenCombine)
import OpenCombine
#endif

/// Shape: a client protocol, used as a bare existential (`let search: SearchClient`) by other modules.
@JavaExport
public protocol SearchClient: Sendable {
  var id: String { get }
  var name: String { get }
  func search(query: String) async throws -> [Book]
}

/// Shape: a protocol extension implementing a requirement and adding a method.
extension SearchClient {
  public var name: String { "search \(id)" }

  public func uid() -> String {
    "\(id)::uid"
  }
}

/// Shape: a conformer that declares neither `name` nor `uid()`.
@JavaExport
public final class SearchClientMock: SearchClient {
  public let id: String
  private let books: [Book]

  public init(id: String, books: [Book]) {
    self.id = id
    self.books = books
  }

  public func search(query: String) async throws -> [Book] {
    guard !query.isEmpty else {
      throw LibraryError.notFound(id: query)
    }
    return books.filter { $0.title.localizedCaseInsensitiveContains(query) }
  }
}

/// Shape: a requirement taking a closure, so conformers must take the protocol's functional interface.
@JavaExport
public protocol NotificationsClient: Sendable {
  func onAuthError(_ handler: @escaping @Sendable () -> Void)
  func notify(_ message: Message)
}

@JavaExport
public final class NotificationsClientMock: NotificationsClient, @unchecked Sendable {
  private var handlers: [@Sendable () -> Void] = []
  public private(set) var delivered: [String] = []

  public init() {}

  public func onAuthError(_ handler: @escaping @Sendable () -> Void) {
    handlers.append(handler)
  }

  public func notify(_ message: Message) {
    switch message {
    case .string(let text): delivered.append(text)
    case .closed(let code, let reason): delivered.append("closed \(code) \(reason ?? "")")
    }
  }

  public func failAuth() {
    handlers.forEach { $0() }
  }

  public var deliveredCount: Int64 { Int64(delivered.count) }
}

/// Shape: an extension, in this module, of another module's type.
extension Book {
  @JavaExport
  public func shareText() -> String {
    "\(title) (\(pages) pages)"
  }
}

/// Shape: dictionaries and sets of another module's types.
@JavaExport
public struct CatalogClient: Sendable {
  private let shelves: [ShelfID: Shelf]

  public init(shelves: [Shelf]) {
    self.shelves = Dictionary(uniqueKeysWithValues: shelves.map { ($0.id, $0) })
  }

  public func all() -> [ShelfID: Shelf] {
    shelves
  }

  public func ids() -> Set<ShelfID> {
    Set(shelves.keys)
  }

  /// Shape: a protocol, of another module, returned by a closure.
  /// Gap: closures returning `any P` aren't supported yet.
  @JavaExport(false)
  public func makeSearch() -> () -> any SearchClient {
    let books = shelves.values.flatMap(\.books)
    return { SearchClientMock(id: "catalog", books: books) }
  }
}

/// Shape: Combine state, observed from Swift; Java reads the current value.
@JavaExport
public final class DownloadProgress: @unchecked Sendable {
  private let subject = CurrentValueSubject<Double, Never>(0)

  public init() {}

  @JavaExport(false)
  public var publisher: AnyPublisher<Double, Never> {
    subject.eraseToAnyPublisher()
  }

  public var current: Double { subject.value }

  public func advance(by amount: Double) {
    subject.send(min(1, subject.value + amount))
  }
}
