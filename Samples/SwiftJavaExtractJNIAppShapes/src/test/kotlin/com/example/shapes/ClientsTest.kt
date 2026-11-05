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

import com.example.shapes.clients.CatalogClient
import com.example.shapes.clients.DownloadProgress
import com.example.shapes.clients.NotificationsClient
import com.example.shapes.clients.NotificationsClientMock
import com.example.shapes.clients.SearchClient
import com.example.shapes.clients.SearchClientMock
import com.example.shapes.models.Book
import com.example.shapes.models.LibraryError
import com.example.shapes.models.Message
import com.example.shapes.models.Shelf
import com.example.shapes.models.ShelfID
import java.util.concurrent.ExecutionException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs

class ClientsTest {
    private val books = arrayOf(Book.init("1", "Cosmos"), Book.init("2", "Cosmic Dust"), Book.init("3", "History"))

    @Test
    fun protocolExtensionMembersAndAsyncRequirements() {
        val search: SearchClient = SearchClientMock.init("mock", books)
        assertEquals("search mock", search.name)   // implemented by the protocol extension
        assertEquals(2, search.search("cosm").get().size)
        val failure = assertFailsWith<ExecutionException> { search.search("").get() }
        assertIs<LibraryError>(failure.cause)
    }

    @Test
    fun requirementTakingAClosure() {
        val mock = NotificationsClientMock.init()
        val client: NotificationsClient = mock
        var failures = 0
        client.onAuthError { failures++ }
        mock.failAuth()
        assertEquals(1, failures)

        client.notify_(Message.string("hi"))
        assertEquals(listOf("hi"), mock.delivered.toList())
    }

    @Test
    fun dictionariesOfAnotherModulesTypes() {
        val catalog = CatalogClient.init(arrayOf(Shelf.init(ShelfID.init("a"), books), Shelf.init(ShelfID.init("b"), books)))
        val all = catalog.all()
        assertEquals(2, all.size)
        assertEquals(3, all[ShelfID.init("a")]!!.books.size)
        assertEquals(setOf("a", "b"), catalog.ids().map { it.rawValue }.toSet())
    }

    @Test
    fun combineBackedState() {
        val progress = DownloadProgress.init()
        progress.advance(0.25)
        progress.advance(0.25)
        assertEquals(0.5, progress.current)
    }
}
