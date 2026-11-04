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

import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;

import static org.junit.jupiter.api.Assertions.*;

public class AsyncProtocolCallbacksTest {
    static class JavaAsyncCallbacks implements AsyncCallbackProtocol {
        private final boolean fail;

        JavaAsyncCallbacks(boolean fail) {
            this.fail = fail;
        }

        @Override
        public CompletableFuture<Long> fetchValue(long input) {
            return CompletableFuture.supplyAsync(() -> input * 2);
        }

        @Override
        public CompletableFuture<MySwiftClass> fetchObject(long input, SwiftArena swiftArena) {
            if (fail) {
                return CompletableFuture.failedFuture(new IllegalStateException("offline"));
            }
            return CompletableFuture.supplyAsync(() -> MySwiftClass.init(input, 0, swiftArena));
        }
    }

    @Test
    void asyncRequirementsAreAwaited() throws Exception {
        // 5 * 2 from fetchValue, plus x = 5 from fetchObject
        assertEquals(15, MySwiftLibrary.callAsyncCallbacks(new JavaAsyncCallbacks(false), 5).get());
    }

    @Test
    void asyncRequirementFailurePropagates() {
        var future = MySwiftLibrary.callAsyncCallbacks(new JavaAsyncCallbacks(true), 5);
        assertThrows(ExecutionException.class, future::get);
    }
}
