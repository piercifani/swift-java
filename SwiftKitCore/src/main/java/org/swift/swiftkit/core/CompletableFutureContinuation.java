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

package org.swift.swiftkit.core;

import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;

/**
 * Resumes a suspended Swift task when a {@link CompletableFuture} completes.
 * <p>
 * Used when Swift awaits a future returned by a Java implementation of an {@code async}
 * Swift protocol requirement: no thread blocks while the future is pending.
 */
public final class CompletableFutureContinuation {
    private CompletableFutureContinuation() {}

    /**
     * Resumes the Swift continuation at {@code continuation} exactly once, when {@code future}
     * completes normally, exceptionally, or is cancelled.
     */
    public static void resumeWhenComplete(CompletableFuture<?> future, long continuation) {
        future.whenComplete((value, error) -> {
            Throwable cause = error instanceof CompletionException && error.getCause() != null ? error.getCause() : error;
            $resume(continuation, value, cause);
        });
    }

    private static native void $resume(long continuation, Object value, Throwable error);
}
