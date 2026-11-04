//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift.org project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift.org project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

package com.example.swift;

import org.junit.jupiter.api.Test;
import org.swift.swiftkit.core.SwiftArena;

import static org.junit.jupiter.api.Assertions.*;

public class ClassHierarchyTest {
    @Test
    void subclassIsASuperclass() {
        try (var arena = SwiftArena.ofConfined()) {
            Square square = Square.init(3, arena);
            Shape shape = square;
            assertEquals("square: 9.0", shape.describe());
            assertEquals(3, square.getSide());
            assertEquals(13, MySwiftLibrary.totalArea(new Shape[] { square, Square.init(2, arena) }));
        }
    }

    @Test
    void returnedInstanceHasItsDynamicClass() {
        try (var arena = SwiftArena.ofConfined()) {
            Shape shape = MySwiftLibrary.makeSquareShape(4, arena);
            assertInstanceOf(Square.class, shape);
            assertEquals(16, shape.area());
        }
    }

    @Test
    void wrappersOfTheSameInstanceAreEqual() {
        try (var arena = SwiftArena.ofConfined()) {
            Square square = Square.init(2, arena);
            Shape same = MySwiftLibrary.sameShape(square, arena);
            assertNotSame(square, same);
            assertEquals(square, same);
            assertEquals(square.hashCode(), same.hashCode());
            assertNotEquals(square, Square.init(2, arena));
        }
    }
}
