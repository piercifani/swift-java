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

// `@JavaExport(false)` keeps Swift-only members out of the Kotlin API without failing the build.
class ExportControlTest {
    @Test
    fun exportedMembersStay() {
        assertEquals("ann", SessionInfo.init("ann").userName)
    }

    @Test
    fun optedOutMembersAreMissing() {
        val names = SessionInfo::class.java.methods.map { it.name }
        assertTrue("debugPairs" !in names, "$names")
        assertTrue("getDebugDump" !in names, "$names")
    }
}
