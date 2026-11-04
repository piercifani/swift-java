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

// Main-actor members check that they run on the main thread. Only on macOS can the JVM test thread
// be the process's main thread (`-XstartOnFirstThread`), as Android's UI thread is.
@EnabledOnOs(OS.MAC)
class MainActorTest {
    @Test
    fun propertiesAndMethods() {
        val vm = CounterViewModel.init("Counter")
        assertEquals("Counter", vm.title)
        vm.increment()
        vm.increment()
        assertEquals(2, vm.count)
        vm.title = "Renamed"
        assertEquals("Renamed", vm.title)
    }
}
