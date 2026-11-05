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

import com.example.shapes.dependencies.AppState
import com.example.shapes.dependencies.Dependencies
import com.example.shapes.dependencies.Reader
import com.example.shapes.dependencies.System
import com.example.shapes.models.Book
import com.example.shapes.models.LibraryError
import com.example.shapes.models.Scheme
import java.util.concurrent.ExecutionException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs

class DependenciesTest {
    @Test
    fun clientsTypedAsAnotherModulesProtocols() {
        val clients = Dependencies.preview().clients
        assertEquals("search mock", clients.search.name)
        assertEquals(1, clients.search.search("cosmos").get().size)
        assertEquals(1, clients.catalog.all().size)
    }

    @Test
    fun autoclosureConfiguration() {
        var reads = 0
        val system = System.init({ reads++; Scheme.release() }, { "Library" })
        assertEquals(0, reads)   // evaluated only when read
        assertEquals("Library", system.appName.invoke())
        assertEquals(Scheme.release().toDebugString(), system.scheme.invoke().toDebugString())
        assertEquals(1, reads)
    }

    @Test
    fun asyncFunctionsTakingEntities() {
        val state = AppState.init()
        val book = Book.init("1", "Cosmos")
        val offline = assertFailsWith<ExecutionException> { state.borrow(book).get() }
        assertIs<LibraryError>(offline.cause)

        state.connect(Reader.init("Ada")).get()
        assertEquals("Ada", state.reader!!.name)
        assertEquals(14, state.borrow(book).get().days)
        state.connect(null).get()
    }
}
