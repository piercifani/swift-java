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
import org.swift.swiftkit.core.SwiftErrorException;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;

public class ErrorValuesTest {
    @Test
    void jextractedErrorRoundTrip() {
        Throwable error = ErrorValues.make(true).orElseThrow();
        assertInstanceOf(SampleError.class, error);
        // Back in Swift, it's the same case.
        assertTrue(ErrorValues.isOffline(error));
        assertTrue(ErrorValues.make(false).isEmpty());
    }

    @Test
    void otherSwiftErrorRoundTrip() {
        Throwable error = ErrorValues.coded(7);
        assertInstanceOf(SwiftErrorException.class, error);
        assertEquals(7, ErrorValues.code(error));
    }

    @Test
    void javaExceptionRoundTrip() {
        IllegalStateException exception = new IllegalStateException("offline");
        assertTrue(ErrorValues.describe(exception).contains("offline"));
        assertFalse(ErrorValues.isOffline(exception));
        // A Java exception comes back as the same object.
        assertSame(exception, ErrorValues.roundTrip(Optional.of(exception)).orElseThrow());
        assertTrue(ErrorValues.roundTrip(Optional.empty()).isEmpty());
    }

    @Test
    void closureArguments() {
        List<Optional<Throwable>> seen = new ArrayList<>();
        ErrorValues.report(seen::add);
        assertEquals(2, seen.size());
        assertInstanceOf(SampleError.class, seen.get(0).orElseThrow());
        assertTrue(seen.get(1).isEmpty());
    }

    @Test
    void returnedClosure() {
        ErrorValues.makeLogger.result log = ErrorValues.makeLogger();
        assertTrue(log.apply(new RuntimeException("disk full")).contains("disk full"));
    }
}
