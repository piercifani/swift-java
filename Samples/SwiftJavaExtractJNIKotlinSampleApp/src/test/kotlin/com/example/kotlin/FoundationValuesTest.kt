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

import java.net.URI
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNull

// URL, Date, Data, Locale and TimeZone are java.net.URI, java.util.Date, ByteArray, java.util.Locale and
// java.util.TimeZone in Kotlin, and CGFloat is a Double.
class FoundationValuesTest {
    private fun bookmark() = Bookmark.init(
        URI.create("https://swift.org/docs"),
        null,
        Date(1_700_000_000_123),
        byteArrayOf(1, 2, -1),
        Locale.forLanguageTag("pt-BR"),
        TimeZone.getTimeZone("Europe/Rome"),
        1.5,
    )

    @Test
    fun valuesRoundTrip() {
        val bookmark = bookmark()
        assertEquals(URI.create("https://swift.org/docs"), bookmark.url)
        assertNull(bookmark.icon)
        bookmark.icon = URI.create("https://swift.org/favicon.ico")
        assertEquals("https://swift.org/favicon.ico", bookmark.icon.toString())
        assertEquals(1_700_000_000_123, bookmark.created.time)
        assertContentEquals(byteArrayOf(1, 2, -1), bookmark.thumbnail)
        assertEquals("pt-BR", bookmark.locale.toLanguageTag())
        assertEquals("Europe/Rome", bookmark.timeZone.id)
        assertEquals(1.5, bookmark.zoom)
        assertEquals(listOf("https://swift.org/docs", "https://swift.org/docs/more"), bookmark.related().map { it.toString() })
    }

    @Test
    fun closures() {
        val bookmark = bookmark()
        val opened = mutableListOf<URI>()
        bookmark.onOpen = { opened += it }
        bookmark.open()
        assertEquals(listOf(URI.create("https://swift.org/docs")), opened)

        var visit: Pair<URI, Date>? = null
        bookmark.observeVisits { url, date -> visit = url to date }
        assertEquals(URI.create("https://swift.org/docs") to Date(1_700_000_000_123), visit)
    }

    @Test
    fun asyncResult() {
        assertEquals(1_700_000_060_123, bookmark().refreshed().get().time)
    }
}
