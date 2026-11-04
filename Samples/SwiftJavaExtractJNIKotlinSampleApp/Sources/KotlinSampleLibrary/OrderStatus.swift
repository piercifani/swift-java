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

/// Without associated values, so Kotlin gets a Java `enum` (`payloadlessEnumsAsJavaEnums`).
public enum OrderStatus: String, CaseIterable, Sendable {
  case pending
  case filled
  case cancelled

  public var isFinal: Bool { self != .pending }
}

public struct Order: Sendable {
  public var id: String
  public var status: OrderStatus

  public init(id: String, status: OrderStatus) {
    self.id = id
    self.status = status
  }
}

public enum OrderEvent: Sendable {
  case changed(OrderStatus)
}

public enum Orders {
  public static func fill(_ status: OrderStatus) -> OrderStatus {
    status == .pending ? .filled : status
  }

  public static func all() -> [OrderStatus] { OrderStatus.allCases }

  public static func status(of id: String) -> OrderStatus? { id.isEmpty ? nil : .pending }

  public static func byID() -> [String: OrderStatus] { ["a": .filled] }

  public static func event(_ status: OrderStatus) -> OrderEvent { .changed(status) }

  public static func watch(_ onChange: @escaping @Sendable (OrderStatus) -> Void) {
    onChange(.cancelled)
  }

  public static func settle() async -> OrderStatus { .filled }
}
