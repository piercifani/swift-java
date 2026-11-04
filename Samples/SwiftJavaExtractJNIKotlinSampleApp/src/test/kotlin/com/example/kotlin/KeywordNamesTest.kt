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

// Swift names that are Java keywords: parameters get a `_` suffix, `default` drops its backticks, and
// `wait()`, which Java's `Object` already declares, is `wait_()`.
class KeywordNamesTest {
    @Test
    fun keywordNames() {
        val position = Position.init(3, true)
        assertEquals("long side", position.label("long side", "short side"))
        assertEquals(3L, position.wait_())
        assertEquals(0L, Position.getDefault().size)

        val split = Exposure.split(5, 2).case as Exposure.Case.Split
        assertEquals(5L, split.long_)
        assertEquals(2L, split.short_)
    }
}
