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

/// Foundation values cross as standard Java types (`foundationTypesAsJavaTypes`).
public final class Bookmark {
  public var url: URL
  public var icon: URL?
  public var created: Date
  public var thumbnail: Data
  public var locale: Locale
  public var timeZone: TimeZone
  public var zoom: CGFloat
  public var onOpen: ((URL) -> Void)?

  public init(url: URL, icon: URL?, created: Date, thumbnail: Data, locale: Locale, timeZone: TimeZone, zoom: CGFloat) {
    self.url = url
    self.icon = icon
    self.created = created
    self.thumbnail = thumbnail
    self.locale = locale
    self.timeZone = timeZone
    self.zoom = zoom
  }

  public func open() {
    onOpen?(url)
  }

  public func observeVisits(_ onVisit: @escaping (URL, Date) -> Void) {
    onVisit(url, created)
  }

  public func related() -> [URL] {
    [url, url.appendingPathComponent("more")]
  }

  public func refreshed() async -> Date {
    created.addingTimeInterval(60)
  }
}
