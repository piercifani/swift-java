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
import org.swift.swiftkit.core.SwiftAsyncStream;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.*;

public class AsyncStreamTest {
    static <T> List<T> collect(SwiftAsyncStream<T> stream) throws InterruptedException {
        List<T> values = Collections.synchronizedList(new ArrayList<>());
        CountDownLatch done = new CountDownLatch(1);
        stream.subscribe(new SwiftAsyncStream.Subscriber<T>() {
            @Override
            public void onNext(T value) {
                values.add(value);
            }

            @Override
            public void onComplete() {
                done.countDown();
            }
        });
        assertTrue(done.await(5, TimeUnit.SECONDS));
        return values;
    }

    @Test
    void primitiveElements() throws Exception {
        assertEquals(List.of(3L, 2L, 1L, 0L), collect(MySwiftLibrary.countdown(3)));
    }

    @Test
    void jextractedElements() throws Exception {
        try (var arena = SwiftArena.ofConfined()) {
            List<Square> squares = collect(MySwiftLibrary.shapes(2, arena));
            assertEquals(2, squares.size());
            assertEquals(4.0, squares.get(1).area());
        }
    }

    @Test
    void throwingStreamDeliversItsError() throws Exception {
        List<Long> values = Collections.synchronizedList(new ArrayList<>());
        AtomicReference<Throwable> error = new AtomicReference<>();
        CountDownLatch done = new CountDownLatch(1);
        MySwiftLibrary.interruptedCountdown(3, 2).subscribe(new SwiftAsyncStream.Subscriber<Long>() {
            @Override
            public void onNext(Long value) {
                values.add(value);
            }

            @Override
            public void onComplete() {
                done.countDown();
            }

            @Override
            public void onError(Throwable failure) {
                error.set(failure);
                done.countDown();
            }
        });
        assertTrue(done.await(5, TimeUnit.SECONDS));
        assertEquals(List.of(3L, 2L), values);
        assertNotNull(error.get());
        assertEquals("interrupted", error.get().getMessage());
    }

    @Test
    void canOnlyBeSubscribedOnce() throws Exception {
        SwiftAsyncStream<Long> stream = MySwiftLibrary.countdown(1);
        collect(stream);
        assertThrows(IllegalStateException.class, () -> stream.subscribe(value -> {}));
    }
}
