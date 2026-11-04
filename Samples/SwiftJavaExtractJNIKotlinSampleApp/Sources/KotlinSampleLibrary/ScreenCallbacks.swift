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

/// Closures a view model hands to its screen. The UI calls the main-actor ones on the main thread;
/// async ones return a `CompletableFuture`.
@MainActor
public final class ScreenModel {
  public private(set) var events: [String] = []

  public init() {}

  public var onTap: @MainActor () -> Void {
    { [unowned self] in events.append("tap") }
  }

  public var onSelect: @MainActor (String) -> Void {
    { [unowned self] row in events.append("select \(row)") }
  }

  public var title: @MainActor () -> String {
    { "Markets" }
  }

  public var onDismiss: (@MainActor () -> Void)? {
    { [unowned self] in events.append("dismiss") }
  }

  public var count: @Sendable (String) async -> Int64 {
    { text in Int64(text.count) }
  }

  public var save: @MainActor (String) async throws -> Void {
    { [unowned self] name in
      guard !name.isEmpty else {
        throw ScreenError.emptyName
      }
      events.append("save \(name)")
    }
  }
}

public enum ScreenError: Error {
  case emptyName
}
