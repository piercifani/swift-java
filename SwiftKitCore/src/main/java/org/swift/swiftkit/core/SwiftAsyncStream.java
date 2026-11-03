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

import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.Function;

/**
 * A Swift {@code AsyncStream} returned to Java.
 * <p>
 * {@link #subscribe(Subscriber)} starts a Swift task that iterates the stream and delivers each
 * element to the subscriber, without blocking a Java thread. An {@code AsyncStream} has a single
 * consumer, so a stream (and any {@link #map mapped} view of it) can be subscribed to once.
 *
 * @param <T> the element type
 */
public final class SwiftAsyncStream<T> {
    /** Receives the elements of a stream, on the thread of the Swift task iterating it. */
    public interface Subscriber<T> {
        void onNext(T value);

        /** The stream finished (it is not called when the subscription is cancelled). */
        default void onComplete() {}
    }

    /** Cancels the Swift task iterating the stream; elements stop arriving. */
    public interface Subscription {
        void cancel();
    }

    /** The Swift stream, shared by a stream and its mapped views until it is subscribed to. */
    private static final class Source {
        private final AtomicLong handle = new AtomicLong(0);
    }

    private final Source source;
    private final Function<Object, ? extends T> mapper;

    @SuppressWarnings("unchecked")
    public SwiftAsyncStream() {
        this(new Source(), value -> (T) value);
    }

    private SwiftAsyncStream(Source source, Function<Object, ? extends T> mapper) {
        this.source = source;
        this.mapper = mapper;
    }

    /** Called from Swift with the handle of the Swift stream. */
    void attachSource(long handle) {
        source.handle.set(handle);
    }

    /** A view of this stream whose elements are transformed by {@code transform}. */
    public <R> SwiftAsyncStream<R> map(Function<? super T, ? extends R> transform) {
        return new SwiftAsyncStream<>(source, mapper.andThen(transform));
    }

    /**
     * Starts iterating the Swift stream.
     *
     * @throws IllegalStateException if this stream was already subscribed to
     */
    public Subscription subscribe(Subscriber<? super T> subscriber) {
        long handle = source.handle.getAndSet(0);
        if (handle == 0) {
            throw new IllegalStateException("A Swift AsyncStream can only be subscribed to once");
        }
        Delivery delivery = new Delivery(value -> subscriber.onNext(mapper.apply(value)), subscriber::onComplete);
        delivery.started($subscribe(handle, delivery));
        return delivery::cancel;
    }

    /** Called by the Swift task; owns its task handle and releases it exactly once. */
    private static final class Delivery {
        private final java.util.function.Consumer<Object> next;
        private final Runnable complete;
        private final AtomicLong task = new AtomicLong(0);
        private final AtomicBoolean finished = new AtomicBoolean(false);

        Delivery(java.util.function.Consumer<Object> next, Runnable complete) {
            this.next = next;
            this.complete = complete;
        }

        void next(Object value) {
            next.accept(value);
        }

        void finish(boolean completed) {
            if (finished.compareAndSet(false, true)) {
                release();
                if (completed) {
                    complete.run();
                }
            }
        }

        void started(long handle) {
            task.set(handle);
            // Finished or cancelled before $subscribe returned: cancel (harmless if already done) and release.
            if (finished.get()) {
                long started = task.getAndSet(0);
                if (started != 0) {
                    $cancelTask(started);
                    $releaseTask(started);
                }
            }
        }

        void cancel() {
            long handle = task.getAndSet(0);
            if (handle != 0) {
                $cancelTask(handle);
                $releaseTask(handle);
            }
            finished.set(true);
        }

        private void release() {
            long handle = task.getAndSet(0);
            if (handle != 0) {
                $releaseTask(handle);
            }
        }
    }

    private static native long $subscribe(long source, Object delivery);

    private static native void $cancelTask(long task);

    private static native void $releaseTask(long task);
}
