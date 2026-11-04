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
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertSame
import kotlin.test.assertTrue

class JavaEnumsTest {
    @Test
    fun exhaustiveWhen() {
        val label = when (Orders.fill(OrderStatus.pending)) {
            OrderStatus.pending -> "pending"
            OrderStatus.filled -> "filled"
            OrderStatus.cancelled -> "cancelled"
        }
        assertEquals("filled", label)
    }

    @Test
    fun constantsAreTheValuesSwiftReturns() {
        assertSame(OrderStatus.filled, Orders.fill(OrderStatus.pending))
        assertEquals(OrderStatus.entries, Orders.all().toList())
        assertEquals("cancelled", OrderStatus.cancelled.rawValue)
        assertTrue(OrderStatus.cancelled.isFinal)
    }

    @Test
    fun everywhereAValueCrosses() = runBlocking {
        assertSame(OrderStatus.pending, Orders.status("a"))
        assertSame(OrderStatus.filled, Orders.byID()["a"])
        assertSame(OrderStatus.cancelled, Order.init("a", OrderStatus.cancelled).status)
        assertSame(OrderStatus.filled, (Orders.event(OrderStatus.filled).case as OrderEvent.Case.Changed).arg0)
        var seen: OrderStatus? = null
        Orders.watch { seen = it }
        assertSame(OrderStatus.cancelled, seen)
        assertSame(OrderStatus.filled, Orders.settle().await())
    }

    @Test
    fun manyRoundTrips() {
        repeat(10_000) { assertSame(OrderStatus.filled, Orders.fill(OrderStatus.filled)) }
    }
}
