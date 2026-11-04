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

/**
 * Propagates cancellation of the {@link CompletableFuture} returned for an {@code async} Swift
 * function to the Swift {@code Task} running it.
 */
public final class CompletableFutureCancellation {
    private CompletableFutureCancellation() {}

    /**
     * Cancels {@code source} when {@code result}, a future derived from it, is cancelled.
     * Cancelling a derived future (e.g. from {@code thenApply}) does not otherwise reach its source.
     */
    public static <T> CompletableFuture<T> forwardCancellation(CompletableFuture<T> result, CompletableFuture<?> source) {
        result.whenComplete((value, error) -> {
            if (result.isCancelled()) {
                source.cancel(true);
            }
        });
        return result;
    }

    /**
     * Cancels the Swift task at {@code task} if {@code future} is cancelled, and releases the task
     * handle once {@code future} completes in any way.
     */
    public static void cancelTaskWhenCancelled(CompletableFuture<?> future, long task) {
        future.whenComplete((value, error) -> {
            if (future.isCancelled()) {
                $cancelTask(task);
            }
            $releaseTask(task);
        });
    }

    private static native void $cancelTask(long task);

    private static native void $releaseTask(long task);
}
