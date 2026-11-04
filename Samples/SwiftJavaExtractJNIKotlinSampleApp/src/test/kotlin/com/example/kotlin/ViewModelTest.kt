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

import org.junit.jupiter.api.condition.EnabledOnOs
import org.junit.jupiter.api.condition.OS
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

// A view model as Compose code uses it. Main-actor isolated, so macOS only (see MainActorTest).
@EnabledOnOs(OS.MAC)
class ViewModelTest {
    @Test
    fun viewModelLifecycle() {
        val opened = mutableListOf<String>()
        var closed = false
        val vm = MarketViewModel.init(MarketViewModel.Callbacks.init({ market -> opened += market.id }, { closed = true }))
        val base: BaseViewModel = vm
        base.setup()
        assertEquals(1, vm.markets.size)

        // `load()` is main-actor isolated: pump the main loop instead of blocking the main thread on
        // the future (on Android the main looper runs it while the caller suspends).
        val loaded = vm.load()
        val deadline = System.currentTimeMillis() + 10_000
        while (!loaded.isDone && System.currentTimeMillis() < deadline) MainLoop.run(0.01)
        loaded.get()
        assertFalse(vm.isLoading)
        assertEquals(2, vm.markets.size)

        vm.send(MarketViewModel.Input.tapped(vm.markets[1]))
        vm.send(MarketViewModel.Input.closeTapped())
        assertEquals(listOf("2"), opened)
        assertEquals(true, closed)
    }
}
