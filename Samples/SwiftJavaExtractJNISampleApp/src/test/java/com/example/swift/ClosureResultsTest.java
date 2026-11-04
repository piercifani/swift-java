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

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;

public class ClosureResultsTest {
    @Test
    void returnedPrimitiveClosure() {
        try (var arena = SwiftArena.ofConfined()) {
            ClosureFactory.makeAdder.result add = ClosureFactory.init(arena).makeAdder(10);
            assertEquals(15, add.apply(5));
            long sum = 0;
            for (int i = 0; i < 1000; i++) {
                sum += add.apply(i);
            }
            assertEquals(10 * 1000 + 999 * 1000 / 2, sum);
        }
    }

    @Test
    void returnedStructClosure() {
        try (var arena = SwiftArena.ofConfined()) {
            var describe = ClosureFactory.init(arena).makeDescriber();
            assertEquals("cap: 3", describe.apply(MySwiftStruct.init(3, 1, arena), "cap: "));
        }
    }

    @Test
    void droppedClosureIsReleased() throws InterruptedException {
        long before = ClosureFactory.getReleasedClosures();
        for (int i = 0; i < 100; i++) {
            assertEquals(1, ClosureFactory.makeTracked().apply());
        }
        long deadline = System.currentTimeMillis() + 10_000;
        while (ClosureFactory.getReleasedClosures() == before && System.currentTimeMillis() < deadline) {
            System.gc();
            Thread.sleep(10);
        }
        assertTrue(ClosureFactory.getReleasedClosures() > before);
    }

    @Test
    void optionalClosureProperty() {
        try (var arena = SwiftArena.ofConfined()) {
            ClosureFactory factory = ClosureFactory.init(arena);
            assertTrue(factory.getOnStruct().isEmpty());

            List<Long> seen = new ArrayList<>();
            factory.setOnStruct(Optional.of(value -> seen.add(value.getCapacity())));
            factory.send(MySwiftStruct.init(1, 0, arena));
            // The getter returns the Swift closure, which calls the Java lambda set above.
            factory.getOnStruct().get().apply(MySwiftStruct.init(2, 0, arena));
            factory.setOnStruct(Optional.empty());
            factory.send(MySwiftStruct.init(3, 0, arena));
            assertEquals(List.of(1L, 2L), seen);
        }
    }
}
