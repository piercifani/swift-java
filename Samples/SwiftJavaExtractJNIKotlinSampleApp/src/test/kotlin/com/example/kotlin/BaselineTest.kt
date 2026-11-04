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

import com.example.kotlin.models.Tag
import kotlinx.coroutines.future.await
import kotlinx.coroutines.runBlocking
import org.swift.swiftkit.core.SwiftArena
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs

class BaselineTest {
    @Test
    fun structRoundTrip() {
        val item = Item.init("a", 2)
        assertEquals("a", item.id)
        assertEquals(2, item.count)
        assertEquals(Item.init("a", 2), item)
        assertEquals(Item.init("a", 2).hashCode(), item.hashCode())
    }

    @Test
    fun throwsBecomesAnException() {
        val store = Store.init()
        assertEquals("x", store.item("x").id)
        assertFailsWith<Exception> { store.item("") }
    }

    @Test
    fun asyncIsAFuture() = runBlocking {
        assertEquals("x", Store.init().load("x").await().id)
    }

    @Test
    fun enumWithPayload() {
        val route = Store.init().route(Item.init("a", 1))
        val case = route.getCase(SwiftArena.ofAuto())
        assertIs<Route.Case.Detail>(case)
        assertEquals("a", case.arg0.id)
    }

    @Test
    fun typeFromAnotherModule() {
        assertEquals("tag:a", Store.init().label(Item.init("a", 1), Tag.init("tag")))
    }
}
