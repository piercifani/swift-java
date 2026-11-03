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

package org.swift.swiftkit.kotlin

import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.channels.trySendBlocking
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import org.swift.swiftkit.core.SwiftAsyncStream

/**
 * A Swift `AsyncStream` or `AsyncThrowingStream` as a cold [Flow]. Collecting it subscribes to the
 * stream, so like the stream it can be collected once; cancelling the collector cancels the Swift
 * task iterating it. An error thrown by the stream is thrown by `collect`.
 *
 * When the collector falls behind, the Swift task waits for buffer space before its next element.
 */
fun <T> SwiftAsyncStream<T>.asFlow(): Flow<T> = callbackFlow {
    val subscription = subscribe(object : SwiftAsyncStream.Subscriber<T> {
        override fun onNext(value: T) {
            trySendBlocking(value)
        }

        override fun onComplete() {
            close()
        }

        override fun onError(error: Throwable) {
            close(error)
        }
    })
    awaitClose { subscription.cancel() }
}
