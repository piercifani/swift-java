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

package com.example.swift;

import org.junit.jupiter.api.Test;
import org.swift.swiftkit.core.SwiftArena;

import static org.junit.jupiter.api.Assertions.*;

public class ObjectIdentityTest {
    @Test
    void wrappersOfTheSameInstanceAreEqual() {
        try (var arena = SwiftArena.ofConfined()) {
            MySwiftClass object = MySwiftClass.init(arena);
            MySwiftClass same = MySwiftLibrary.sameInstance(object, arena);
            assertNotSame(object, same);
            assertEquals(object, same);
            assertEquals(object.hashCode(), same.hashCode());
            assertNotEquals(object, MySwiftClass.init(arena));
        }
    }
}
