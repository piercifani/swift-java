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

package com.example.shapes

import com.example.shapes.models.Availability
import com.example.shapes.models.Book
import com.example.shapes.models.Cover
import com.example.shapes.models.ImageCover
import com.example.shapes.models.LibraryError
import com.example.shapes.models.Message
import com.example.shapes.models.Quantity
import com.example.shapes.models.Rating
import com.example.shapes.models.Review
import com.example.shapes.models.Shelf
import com.example.shapes.models.ShelfID
import com.example.shapes.models.TextCover
import com.example.shapes.util.Formatting
import com.example.shapes.util.Range64
import java.net.URI
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull

class ModelsTest {
    @Test
    fun entitiesAndFoundationValues() {
        val book = Book.init("1", "Cosmos", 300)
        assertEquals("Cosmos", book.title)
        assertNull(book.coverURL)
        assertEquals("Untitled", Book.getDefault().title)
        val range = book.pageRange!!
        assertEquals(1L, range.first().asLong)
        assertEquals(300L, range.last().asLong)
    }

    @Test
    fun nestedArrays() {
        val books = (1..5).map { Book.init("$it", "Book $it") }.toTypedArray()
        val shelf = Shelf.init(ShelfID.init("s"), books)
        val sections = shelf.sections(2)
        assertEquals(listOf(2, 2, 1), sections.map { it.size })
        assertEquals("Book 5", sections[2][0].title)
        assertEquals(5, Shelf.merge(sections, ShelfID.init("t")).books.size)
    }

    @Test
    fun overloadsAndClashingNames() {
        assertEquals("image https://example.com/c.png", Cover.init(ImageCover.init(URI("https://example.com/c.png"))).summary)
        assertEquals("text Title", Cover.init(TextCover.init("Title")).summary)

        val availability = Availability.init(true, "Now")
        assertEquals(true, availability.getLive())
        assertEquals(true, availability.isLive)
        assertEquals("Now", availability.title)
        assertEquals("Availability", Availability.getTitle_())

        assertEquals(2.5, Quantity.init(2.5).value)
        assertEquals("4: good", Review.init(Rating.init(4), "good").summary)
    }

    @Test
    fun javaKeywordsAndObjectMethods() {
        val range = Range64.init(10, 3)
        assertEquals(10, range.long)
        assertEquals(7, range.wait_())
        assertEquals(2, Formatting.getDefaultPrecision())
        assertEquals("50%", Formatting.percent(0.5))
        assertEquals("shown", Formatting.describe({ "shown" }, true))
    }

    @Test
    fun enumPayloads() {
        val failure = LibraryError.failed(IllegalStateException("disk"))
        assertIs<IllegalStateException>(failure.getAsFailed()!!.get().underlying)
        assertEquals("id", LibraryError.notFound("id").getAsNotFound()!!.get().id)

        assertEquals("hello", Message.string("hello").getAsString()!!.get().arg0)
        val closed = Message.closed(1000, "bye").getAsClosed()!!.get()
        assertEquals(1000, closed.code)
        assertEquals("bye", closed.reason.get())
    }
}
