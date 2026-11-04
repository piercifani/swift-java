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

import java.util.Optional
import kotlin.jvm.optionals.getOrNull
import kotlin.test.Test
import kotlin.test.assertEquals

class CollectionsTest {
    @Test
    fun arrayOfOptionals() {
        val ids = Watchlist.quotes().map { it.getOrNull()?.id }
        assertEquals(listOf("a", null, "c"), ids)
    }

    @Test
    fun arrayOfDictionaries() {
        val pages = Watchlist.pages()
        assertEquals(listOf(1, 2), pages.map { it.size })
        assertEquals(3L, pages[1]["c"])
    }

    @Test
    fun passAnArrayOfOptionals() {
        assertEquals(4L, Watchlist.total(arrayOf(Optional.of(1L), Optional.empty(), Optional.of(3L))))
    }
}
