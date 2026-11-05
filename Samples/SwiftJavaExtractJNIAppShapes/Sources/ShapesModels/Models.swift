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
import ShapesUtil
import SwiftJavaAnnotations

// exportMode "annotated": only declarations marked `@JavaExport` (and their members) are exported.

/// Shape: a callback type declared once and used by other modules' view models.
public typealias VoidCallback = @MainActor () -> Void

/// Shape: a Codable entity with Foundation values, a `default` (a Java keyword) and a field Java doesn't see.
@JavaExport
public struct Book: Codable, Hashable, Sendable, Identifiable {
  public let id: String
  public let title: String
  public let pages: Int64
  public let genre: Genre
  public let coverURL: URL?
  public let published: Date
  @JavaExport(false)
  public let rawPayload: Data?

  public init(id: String, title: String, pages: Int64 = 100, genre: Genre = .fiction, coverURL: URL? = nil) {
    self.id = id
    self.title = title
    self.pages = pages
    self.genre = genre
    self.coverURL = coverURL
    self.published = Date(timeIntervalSince1970: 0)
    self.rawPayload = nil
  }

  public static let `default` = Book(id: "0", title: "Untitled")

  /// Shape: an optional labeled tuple.
  public var pageRange: (first: Int64?, last: Int64?)? {
    pages > 0 ? (first: 1, last: pages) : nil
  }

  /// Shape: Codable plumbing, which Kotlin doesn't need.
  @JavaExport(false)
  public static func decode(_ data: Data) throws -> Book {
    try JSONDecoder().decode(Book.self, from: data)
  }
}

/// Shape: a payloadless enum, a Java enum.
@JavaExport
public enum Genre: String, Codable, CaseIterable, Sendable {
  case fiction
  case history
  case science
}

/// Shape: an app scheme, returned by closures in another module.
@JavaExport
public enum Scheme: String, Sendable {
  case debug
  case release
}

/// Shape: a hashable key used in dictionaries across modules.
@JavaExport
public struct ShelfID: Hashable, Sendable {
  public let rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }
}

/// Shape: collections of entities: nested arrays, sets, optional primitive arrays.
@JavaExport
public struct Shelf: Sendable {
  public let id: ShelfID
  public let books: [Book]
  public let tags: Set<String>
  public let pageCounts: [Int64]?

  public init(id: ShelfID, books: [Book], tags: Set<String> = []) {
    self.id = id
    self.books = books
    self.tags = tags
    self.pageCounts = nil
  }

  private init(_ shelf: Shelf, pageCounts: [Int64]?) {
    id = shelf.id
    books = shelf.books
    tags = shelf.tags
    self.pageCounts = pageCounts
  }

  /// Shape: an optional array of primitives as a parameter.
  /// Gap: optional primitive arrays are supported as results, not yet as parameters.
  @JavaExport(false)
  public func withPageCounts(_ pageCounts: [Int64]?) -> Shelf {
    Shelf(self, pageCounts: pageCounts)
  }

  /// Shape: rows of entities.
  public func sections(size: Int64) -> [[Book]] {
    stride(from: 0, to: books.count, by: Int(size)).map { Array(books[$0..<min($0 + Int(size), books.count)]) }
  }

  public static func merge(_ sections: [[Book]], id: ShelfID) -> Shelf {
    Shelf(id: id, books: sections.flatMap { $0 })
  }
}

/// Shape: an enum with payloads, one of which carries the error that caused it.
@JavaExport
public enum LibraryError: Error, Sendable {
  case notFound(id: String)
  case failed(underlying: any Error)
  case offline
}

/// Shape: a case named like the payload type of another case (`string(String)` makes a `Case.String`).
@JavaExport
public enum Message: Sendable {
  case string(String)
  case closed(code: Int64, reason: String?)
}

/// Shape: an unlabeled closure payload.
/// Gap: closure payloads over jextracted types aren't supported yet, and a single case can't be left out.
@JavaExport(false)
public enum SortPolicy {
  case custom((Book, Book) -> Bool)
  case byTitle
}

/// Shape: overloads whose Java signatures differ but whose native ones don't (both take a pointer).
@JavaExport
public struct Cover: Sendable {
  public let summary: String

  public init(image: ImageCover) {
    summary = "image \(image.url.absoluteString)"
  }

  public init(text: TextCover) {
    summary = "text \(text.title)"
  }
}

@JavaExport
public struct ImageCover: Sendable {
  public let url: URL

  public init(url: URL) {
    self.url = url
  }
}

@JavaExport
public struct TextCover: Sendable {
  public let title: String

  public init(title: String) {
    self.title = title
  }
}

/// Shape: accessors with clashing Java names.
@JavaExport
public struct Availability: Sendable {
  /// `isLive()`, as is `isLive` below.
  public let live: Bool
  public var isLive: Bool { live }
  public var title: String
  /// `getTitle()`, as is the instance property.
  public static var title: String { "Availability" }

  public init(live: Bool, title: String) {
    self.live = live
    self.title = title
  }
}

/// Shape: a default-argument overload that would be ambiguous: `init()` also matches the internal one.
@JavaExport
public struct Quantity: Sendable {
  public let value: Double

  init(units: Int64 = 0) {
    value = Double(units)
  }

  public init(amount: Double = 0) {
    value = amount
  }
}

/// Shape: a parameter named like the thunk's own locals.
@JavaExport
public struct Review: Sendable {
  public let summary: String

  public init(result: Rating?, comment: String) {
    summary = "\(result?.stars ?? 0): \(comment)"
  }
}

@JavaExport
public struct Rating: Sendable {
  public let stars: Int64

  public init(stars: Int64) {
    self.stars = stars
  }
}

/// Shape: a type used only from Swift. Public, not exported.
public struct CacheEntry {
  public let key: String
}
