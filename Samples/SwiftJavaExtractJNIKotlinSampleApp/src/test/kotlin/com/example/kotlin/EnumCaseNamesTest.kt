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

import org.swift.swiftkit.core.SwiftArena
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

class EnumCaseNamesTest {
    @Test
    fun caseNamedLikeItsPayload() {
        val case = Router.open("7").getCase(SwiftArena.ofAuto())
        assertIs<Destination.Case.Market>(case)
        assertEquals("7", case.arg0.id)
    }

    @Test
    fun anotherCasesRecordNamedLikeThePayload() {
        val featured = Router.featured("1").getCase(SwiftArena.ofAuto())
        assertIs<Feed.Case.Featured>(featured)
        assertEquals("1", featured.arg0.id)

        val list = Router.list(arrayOf("a", "b")).getCase(SwiftArena.ofAuto())
        assertIs<Feed.Case.List>(list)
        assertEquals(listOf("a", "b"), list.arg0.map { it.id })
    }
}
