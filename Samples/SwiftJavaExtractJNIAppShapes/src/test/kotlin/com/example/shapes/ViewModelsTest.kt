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

import com.example.shapes.dependencies.Dependencies
import com.example.shapes.models.Book
import com.example.shapes.models.Genre
import com.example.shapes.viewmodels.LoginViewModel
import com.example.shapes.viewmodels.MainLoop
import com.example.shapes.viewmodels.ShelfViewModel
import java.net.URI
import java.util.Optional
import java.util.OptionalLong
import java.util.concurrent.CompletableFuture
import org.junit.jupiter.api.condition.EnabledOnOs
import org.junit.jupiter.api.condition.OS
import kotlin.test.Test
import kotlin.test.assertEquals

/// Waits for a main-actor future while running the main loop, as Android's main looper would.
fun <T> CompletableFuture<T>.awaitOnMain(): T {
    val deadline = System.currentTimeMillis() + 10_000
    while (!isDone && System.currentTimeMillis() < deadline) MainLoop.run(0.01)
    return get()
}

// Main-actor view models must be used from the main thread, which on the JVM only macOS can give the
// tests (`-XstartOnFirstThread`), as Android's UI thread does.
@EnabledOnOs(OS.MAC)
class ViewModelsTest {
    @Test
    fun callbacksTypedWithAnotherModulesTypealias() {
        val events = mutableListOf<String>()
        val vm = LoginViewModel.init(LoginViewModel.Callbacks.init({ events += "login" }, { events += "cancel" }))
        vm.submit("ada@example.com")
        vm.submit("")
        assertEquals(listOf("login", "cancel"), events)
        assertEquals("", vm.email)
    }

    @Test
    fun observableViewModelWithManyKindsOfCallbacks() {
        val opened = mutableListOf<String>()
        val selected = mutableListOf<Int>()
        val links = mutableListOf<URI>()
        val verified = mutableListOf<Pair<String?, Long?>>()
        val callbacks = ShelfViewModel.Callbacks.init(
            { book: Book -> opened += book.title },
            { books: Array<Book> -> selected += books.size },
            { urls: Array<URI> -> links += urls },
            { code: Optional<String>, attempt: OptionalLong ->
                verified += code.orElse(null) to (if (attempt.isPresent) attempt.asLong else null)
            },
        )
        val vm = ShelfViewModel.init(Dependencies.preview(), callbacks)
        assertEquals("Library", vm.appName)

        vm.load("a").awaitOnMain()
        assertEquals(false, vm.isLoading)
        assertEquals(2, vm.books.size)

        vm.open(0)
        vm.selectAll()
        vm.verify("1234", 2)
        vm.verify(null, null)
        assertEquals(listOf("A Short History"), opened)
        assertEquals(listOf(2), selected)
        assertEquals(listOf("1234" to 2L, null to null), verified)
    }

    @Test
    fun asyncCallbacksReturnFutures() {
        val shared = mutableListOf<String>()
        val icons = mutableListOf<String?>()
        val callbacks = ShelfViewModel.Callbacks.init(
            { _: Book -> }, { _: Array<Book> -> }, { _: Array<URI> -> }, { _: Optional<String>, _: OptionalLong -> },
            { vm: ShelfViewModel, genre: Genre -> shared += "${vm.appName} ${genre.toDebugString()}"; CompletableFuture.completedFuture(null) },
            { name: Optional<String> -> icons += name.orElse(null); CompletableFuture.completedFuture(null) },
        )
        val vm = ShelfViewModel.init(Dependencies.preview(), callbacks)
        vm.share(Genre.science()).awaitOnMain()
        vm.setIcon("dark").awaitOnMain()
        vm.setIcon(null).awaitOnMain()
        assertEquals(1, shared.size)
        assertEquals(listOf("dark", null), icons)
    }
}
