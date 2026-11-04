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

import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.future.await
import kotlinx.coroutines.future.future
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.condition.EnabledOnOs
import org.junit.jupiter.api.condition.OS
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Kotlin lambdas passed as Swift escaping closures. Functional-interface names follow
// `<Type>.<method>.<parameter>`; Kotlin converts lambdas to them.
@OptIn(DelicateCoroutinesApi::class)
class ClosuresTest {
    @Test
    fun structParameter() {
        val notifier = Notifier.init()
        val seen = mutableListOf<String>()
        notifier.setHandler { item -> seen += item.id }
        notifier.fire("a")
        notifier.fire("b")
        assertEquals(listOf("a", "b"), seen)
    }

    @Test
    fun mixedArityWithOptionalStruct() {
        val calls = mutableListOf<String>()
        val ok = Notifier.init().check { s, i, item -> calls += "$s$i${item.map { it.id }.orElse("-")}"; true }
        assertTrue(ok)
        assertEquals(listOf("a1-", "b2b"), calls)
    }

    @Test
    fun nonEscapingStructClosure() {
        val out = Notifier.init().transform("a") { item -> Item.init(item.id + "!", item.count + 1) }
        assertEquals("a!", out.id)
        assertEquals(2L, out.count)
    }

    @Test
    fun optionalClosureProperty() {
        val notifier = Notifier.init()
        val seen = mutableListOf<String>()
        assertNull(notifier.onItem)
        notifier.onItem = { item -> seen += item.id }
        notifier.emit("a")
        notifier.onItem?.invoke(Item.init("b", 1))   // the Swift closure, calling the lambda
        notifier.onItem = null
        notifier.emit("c")
        assertEquals(listOf("a", "b"), seen)
    }

    @Test
    fun returnedClosure() {
        val format = Notifier.init().makeFormatter("#")
        assertEquals(listOf("#1", "#2"), listOf("1", "2").map { format(Item.init(it, 1)) })
    }

    @Test
    fun asyncClosureIsAwaited() = runBlocking {
        val seen = java.util.concurrent.CopyOnWriteArrayList<String>()
        Notifier.init().perform("z") { item ->
            // A coroutine, as a CompletableFuture
            GlobalScope.future<Void?>(Dispatchers.Default) {
                delay(50)
                seen += item.id
                null
            }
        }.await()
        assertEquals(listOf("z"), seen.toList())
    }

    @Test
    fun sendableClosureCalledFromAnotherThread() {
        val testThread = Thread.currentThread()
        var calledOn: Thread? = null
        var seenId = ""
        Notifier.init().deliverInBackground("bg") { item ->
            calledOn = Thread.currentThread()
            seenId = item.id
        }
        assertEquals("bg", seenId)
        assertNotEquals(testThread, calledOn)
    }

    @Test
    @EnabledOnOs(OS.MAC) // Screen is main-actor isolated, see MainActorTest
    fun mainActorCallbacks() {
        val events = mutableListOf<String>()
        val callbacks = Callbacks.init({ item -> events += "open ${item.id}" }, { events += "close" })
        Screen.open(callbacks, "7")
        assertEquals(listOf("open 7", "close"), events)
    }
}
