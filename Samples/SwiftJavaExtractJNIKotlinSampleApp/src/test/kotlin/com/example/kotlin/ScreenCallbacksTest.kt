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

import java.util.concurrent.CompletableFuture
import java.util.concurrent.ExecutionException
import org.junit.jupiter.api.condition.EnabledOnOs
import org.junit.jupiter.api.condition.OS
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs

// Closures read from Swift: main-actor ones are called on the main thread, as Compose calls a view
// model's callbacks; async ones return a CompletableFuture. Like MainActorTest, this needs the JVM
// test thread to be the main thread, which only macOS allows.
@EnabledOnOs(OS.MAC)
class ScreenCallbacksTest {
    @Test
    fun mainActorClosures() {
        val screen = ScreenModel.init()
        screen.onTap()
        screen.onSelect("BTC")
        assertEquals("Markets", screen.title())
        screen.onDismiss?.invoke()
        assertEquals(listOf("tap", "select BTC", "dismiss"), screen.events.toList())
    }

    @Test
    fun asyncClosures() {
        val screen = ScreenModel.init()
        assertEquals(3L, screen.count("abc").get())

        // `save` runs on the main actor: pump the main loop rather than block the main thread on it.
        val saved = screen.save("draft")
        await(saved)
        assertEquals(listOf("save draft"), screen.events.toList())

        val failed = screen.save("")
        await(failed)
        val error = assertFailsWith<ExecutionException> { failed.get() }
        assertIs<ScreenError>(error.cause)
    }

    private fun await(future: CompletableFuture<*>) {
        val deadline = System.currentTimeMillis() + 5_000
        while (!future.isDone && System.currentTimeMillis() < deadline) MainLoop.run(0.01)
    }
}
