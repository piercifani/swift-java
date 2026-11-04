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
import kotlin.test.assertTrue

class DefaultArgumentsTest {
    @Test
    fun trailingDefaultsCanBeLeftOut() {
        assertEquals("5 USD", Receipts.format(5))
        assertEquals("5 EUR", Receipts.format(5, "EUR"))
        assertEquals("+5 EUR", Receipts.format(5, "EUR", true))
    }

    @Test
    fun defaultedCallbacks() {
        val lines = mutableListOf<String>()
        var failed = false
        val printer = ReceiptPrinter.init({ lines += it }, { failed = true })
        printer.print(5)
        printer.print(-1)
        assertEquals(listOf("5 USD"), lines)
        assertTrue(failed)
        ReceiptPrinter.init().print(5)
    }
}
