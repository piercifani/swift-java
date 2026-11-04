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

/// A protocol whose extension implements one requirement and adds a method. Conformers that don't
/// declare them get both through the Java interface's `default` methods.
public protocol Labeled {
  var id: String { get }
  var title: String { get }
}

extension Labeled {
  public var title: String { "untitled \(id)" }

  public func uid() -> String {
    "\(id)::uid"
  }
}

public struct LabeledItem: Labeled {
  public let id: String

  public init(id: String) {
    self.id = id
  }
}

public final class TitledItem: Labeled {
  public let id: String
  public let title: String

  public init(id: String, title: String) {
    self.id = id
    self.title = title
  }
}

/// A requirement with a closure parameter: conformers take the protocol's functional interface.
public protocol EventSource {
  func onEvent(_ handler: @escaping (Int64, Int64) -> Void)
}

public final class EventSourceImpl: EventSource {
  public init() {}

  public func onEvent(_ handler: @escaping (Int64, Int64) -> Void) {
    handler(1, 2)
  }
}
