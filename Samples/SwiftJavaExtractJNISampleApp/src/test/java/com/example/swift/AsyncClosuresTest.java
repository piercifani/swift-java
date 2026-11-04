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

import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.ExecutionException;

import static org.junit.jupiter.api.Assertions.*;

public class AsyncClosuresTest {
    @Test
    void voidClosureIsAwaited() throws Exception {
        List<Long> seen = new CopyOnWriteArrayList<>();
        AsyncClosures.perform(5, value -> CompletableFuture.runAsync(() -> {
            sleep(50);
            seen.add(value);
        }).thenApply(ignored -> null)).get();
        // Swift returned only after the Java future completed.
        assertEquals(List.of(5L), seen);
    }

    @Test
    void nonEscapingPrimitiveClosure() throws Exception {
        long result = AsyncClosures.addOne(20, value -> CompletableFuture.supplyAsync(() -> value * 2)).get();
        assertEquals(41, result);
    }

    @Test
    void structResult() throws Exception {
        try (var arena = SwiftArena.ofConfined()) {
            long capacity = AsyncClosures.capacity(value ->
                CompletableFuture.supplyAsync(() -> MySwiftStruct.init(value * 3, 0, arena))
            ).get();
            assertEquals(21, capacity);
        }
    }

    @Test
    void failedFutureIsThrownInSwift() {
        ExecutionException error = assertThrows(ExecutionException.class, () ->
            AsyncClosures.capacity(value -> CompletableFuture.failedFuture(new IllegalStateException("offline"))).get()
        );
        assertTrue(error.getCause().getMessage().contains("offline"), error.getCause().toString());
    }

    private static void sleep(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            throw new RuntimeException(e);
        }
    }
}
