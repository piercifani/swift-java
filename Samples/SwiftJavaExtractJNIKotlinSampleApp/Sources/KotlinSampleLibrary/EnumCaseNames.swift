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

/// Enum cases named like a payload type: inside the generated `Case` interface, the record
/// `Case.Market` would shadow the `Market` class.
public struct Market: Sendable {
  public var id: String

  public init(id: String) {
    self.id = id
  }
}

public enum Destination: Sendable {
  case home
  case market(Market)
}

/// Another case's record has the payload's name.
public enum Feed: Sendable {
  case market
  case featured(Market)
  case list([Market])
}

public enum Router {
  public static func open(id: String) -> Destination { .market(Market(id: id)) }
  public static func featured(id: String) -> Feed { .featured(Market(id: id)) }
  public static func list(ids: [String]) -> Feed { .list(ids.map { Market(id: $0) }) }
}
