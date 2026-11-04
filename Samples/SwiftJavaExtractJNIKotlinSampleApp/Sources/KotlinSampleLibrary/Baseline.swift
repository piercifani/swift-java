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

import KotlinSampleModels

public struct Item: Hashable, Sendable {
  public var id: String
  public var count: Int64

  public init(id: String, count: Int64) {
    self.id = id
    self.count = count
  }
}

public enum Route: Sendable {
  case home
  case detail(Item)
}

public enum StoreError: Error {
  case notFound
}

public final class Store: Sendable {
  public init() {}

  public func item(id: String) throws -> Item {
    if id.isEmpty { throw StoreError.notFound }
    return Item(id: id, count: 1)
  }

  public func load(id: String) async throws -> Item {
    try item(id: id)
  }

  public func route(for item: Item) -> Route {
    .detail(item)
  }

  /// Takes a type from another module.
  public func label(_ item: Item, tag: Tag) -> String {
    "\(tag.name):\(item.id)"
  }
}
