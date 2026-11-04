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


/// Swift subclasses become Java subclasses.
open class Shape {
  public let name: String

  public init(name: String) {
    self.name = name
  }

  open func area() -> Double { 0 }

  public func describe() -> String { "\(name): \(area())" }
}

public final class Square: Shape {
  public let side: Double

  public init(side: Double) {
    self.side = side
    super.init(name: "square")
  }

  public override func area() -> Double { side * side }
}

public func totalArea(_ shapes: [Shape]) -> Double {
  shapes.reduce(0) { $0 + $1.area() }
}

/// Returned as `Shape`; Java receives a `Square`.
public func makeSquareShape(side: Double) -> Shape {
  Square(side: side)
}

/// Returns the same instance: Java gets a new wrapper, which must equal the original.
public func sameShape(_ shape: Shape) -> Shape {
  shape
}
