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
import SwiftJavaAnnotations

// exportMode "all": every public declaration is exported unless marked `@JavaExport(false)`.

/// Shape: a namespace enum of static helpers, with constants inferred from literals.
public enum Formatting {
  /// Shape: no type annotation, inferred from the literal.
  public static let defaultPrecision = 2

  public static func percent(_ value: Double, precision: Int64 = 0) -> String {
    String(format: "%.\(precision)f%%", value * 100)
  }

  /// Shape: a Foundation formatter used from Swift only. Public, but not for Java.
  @JavaExport(false)
  public static func dateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter
  }

  /// Shape: an `@autoclosure` argument, evaluated only when needed.
  public static func describe(_ value: @autoclosure () -> String, when condition: Bool) -> String {
    condition ? value() : ""
  }
}

/// Shape: an identifier helper whose parameters are Java keywords.
public struct Range64: Hashable, Sendable {
  public let long: Int64
  public let short: Int64

  public init(long: Int64, short: Int64) {
    self.long = long
    self.short = short
  }

  /// Shape: a method named like a final `java.lang.Object` method.
  public func wait() -> Int64 {
    long - short
  }
}

/// Shape: platform-specific API. Only Android builds have it.
public enum Platform {
  public static func name() -> String {
    #if os(Android)
    "android"
    #else
    "apple"
    #endif
  }

  #if os(Android)
  /// Gap: jextract extracts every `#if` branch unless given a static build configuration, and the
  /// thunks don't keep the condition, so a macOS build sees a thunk for Android-only API.
  @JavaExport(false)
  public static func androidOnly() -> String {
    "android"
  }
  #endif
}
