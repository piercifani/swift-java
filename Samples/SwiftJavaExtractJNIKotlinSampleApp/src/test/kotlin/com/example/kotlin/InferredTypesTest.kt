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

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class InferredTypesTest {
    @Test
    fun intClosures() {
        assertEquals(10L, Arithmetic.apply({ it * 2 }, 5))
        assertEquals(5L, Arithmetic.combine(2, 3) { a, b -> a + b })
    }

    @Test
    fun unannotatedProperties() {
        val settings = Settings.init()
        assertEquals(42L, Settings.getMaximumCount())
        assertFalse(settings.isEnabled)
        assertEquals("Untitled", settings.title)
        assertEquals(0.5, settings.ratio)
        assertEquals("featured", settings.featured.id)

        settings.title = "Renamed"
        assertEquals("Renamed", settings.title)
    }
}
