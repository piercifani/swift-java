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

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class NullablesTest {
    @Test
    fun nullableResults() {
        val quote: Quote? = Quotes.last("a")
        assertEquals(1.5, quote?.price)
        assertNull(quote?.note)
        assertNull(Quotes.last(""))
        assertEquals(10L, Quotes.volume("a"))
        assertNull(Quotes.volume("b"))
    }

    @Test
    fun nullableParameters() {
        assertEquals("1.5 -", Quotes.describe(1.5, null))
        assertEquals("- 3", Quotes.describe(null, 3L))
        assertEquals(false, Quotes.invert(true))
        assertNull(Quotes.invert(null))
    }

    @Test
    fun nullableProperties() {
        val quote = Quote.init("b")
        quote.note = "watch"
        assertEquals("watch", quote.note)
        quote.note = null
        assertNull(quote.note)
    }

    // With `nullableAnnotation` and `nonNullAnnotation`, Kotlin infers `Quote?` and `String`, not `Quote!` and `String!`.
    @Test
    fun annotatedTypes() {
        val quote = Quotes.last("a")
        val price: Double = quote?.price ?: 0.0
        assertEquals(1.5, price)
        val text: String = Quotes.describe(null, 3L)
        assertEquals("- 3", text)
    }
}
