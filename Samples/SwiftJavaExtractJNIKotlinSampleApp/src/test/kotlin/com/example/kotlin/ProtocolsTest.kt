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

import com.example.kotlin.models.Profile
import com.example.kotlin.models.ProfileClient
import kotlinx.coroutines.future.await
import kotlinx.coroutines.runBlocking
import org.swift.swiftkit.core.SwiftArena
import java.util.concurrent.CompletableFuture
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/// A Kotlin implementation of a Swift protocol. Requirements returning Swift types receive the
/// arena to allocate in; `async` requirements return a CompletableFuture.
class KotlinProfileClient(
    private val fail: Boolean = false,
    private val pending: CompletableFuture<Profile>? = null,
) : ProfileClient {
    override fun displayName(id: String): String = "user-$id"

    override fun profile(id: String, swiftArena: SwiftArena): Profile = Profile.init("profile-$id", swiftArena)

    override fun fetch(id: String, swiftArena: SwiftArena): CompletableFuture<Profile> =
        pending
            ?: if (fail) {
                CompletableFuture.failedFuture(IllegalStateException("offline"))
            } else {
                CompletableFuture.supplyAsync { Profile.init("fetched-$id", swiftArena) }
            }
}

class ProtocolsTest {
    @Test
    fun syncRequirement() {
        assertEquals("user-1", ProfileService.init(KotlinProfileClient()).title("1"))
    }

    @Test
    fun requirementReturningAStruct() {
        assertEquals("profile-1", ProfileService.init(KotlinProfileClient()).name("1"))
    }

    @Test
    fun asyncRequirement() = runBlocking {
        assertEquals("fetched-1", ProfileService.init(KotlinProfileClient()).load("1").await())
    }

    @Test
    fun asyncRequirementFailure() = runBlocking {
        assertFailsWith<Exception> { ProfileService.init(KotlinProfileClient(fail = true)).load("1").await() }
        Unit
    }

    @Test
    fun cancellingTheSwiftTaskCancelsTheFuture() = runBlocking {
        val pending = CompletableFuture<Profile>()
        val endedWithoutValue = ProfileService.init(KotlinProfileClient(pending = pending)).fetchThenCancel("1").await()
        assertTrue(endedWithoutValue)
        assertTrue(pending.isCancelled)
    }
}
