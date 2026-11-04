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

import com.example.kotlin.models.ClientError
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import org.swift.swiftkit.kotlin.asFlow
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class StreamsTest {
    @Test
    fun collectAsAFlow() = runBlocking {
        val ids = PriceFeed.init().prices(3).asFlow().map { it.id }.toList()
        assertEquals(listOf("price-0", "price-1", "price-2"), ids)
    }

    @Test
    fun aThrowingStreamFailsTheFlowWithTheSwiftError() = runBlocking {
        val ids = mutableListOf<String>()
        val error = assertFailsWith<ClientError> {
            PriceFeed.init().pricesUntilOffline(2).asFlow().collect { ids += it.id }
        }
        assertEquals(listOf("price-0", "price-1"), ids)
        assertTrue(error.case is ClientError.Case.Offline)
    }

    @Test
    fun cancellingTheFlowStopsTheSwiftStream() = runBlocking {
        val feed = PriceFeed.init()
        assertEquals(listOf("update 0", "update 1"), feed.live().asFlow().take(2).toList())

        val deadline = System.currentTimeMillis() + 5_000
        while (!feed.wasStopped() && System.currentTimeMillis() < deadline) Thread.sleep(20)
        assertTrue(feed.wasStopped())
    }
}
