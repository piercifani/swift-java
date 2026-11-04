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

package com.example.kotlin

import kotlinx.coroutines.future.await
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.test.Test
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CancellationTest {
    @Test
    fun cancellingTheCoroutineCancelsTheSwiftTask() = runBlocking {
        val download = Download.init()
        // await() cancels the future when its coroutine is cancelled, here by the timeout.
        val result = withTimeoutOrNull(100) { download.run().await() }
        assertNull(result)

        val deadline = System.currentTimeMillis() + 5_000
        while (!download.wasCancelled() && System.currentTimeMillis() < deadline) Thread.sleep(20)
        assertTrue(download.wasCancelled())
    }
}
