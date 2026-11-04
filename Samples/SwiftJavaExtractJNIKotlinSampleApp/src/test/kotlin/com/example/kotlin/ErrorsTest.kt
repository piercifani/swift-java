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
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Swift `Error` values are Kotlin `Throwable`s, in both directions.
class ErrorsTest {
    @Test
    fun completionHandler() {
        val seen = mutableListOf<Throwable?>()
        Uploads.upload("") { error -> seen += error.orElse(null) }
        Uploads.upload("a") { error -> seen += error.orElse(null) }
        assertIs<UploadError>(seen[0])
        assertNull(seen[1])
    }

    @Test
    fun resultsAndParameters() {
        val error: Throwable? = Uploads.failure("")
        assertFailsWith<UploadError> { throw error!! }
        assertTrue(Uploads.isRejected(error!!))   // back in Swift, the same case
        assertNull(Uploads.failure("a"))

        val kotlinError = IllegalStateException("disk full")
        assertFalse(Uploads.isRejected(kotlinError))
        assertTrue(Uploads.describe(kotlinError).contains("disk full"))
    }

    @Test
    fun enumCasePayload() {
        val gaveUp = Uploads.retry("a").getAsGaveUp()!!.get()
        assertIs<UploadError>(gaveUp.underlying)
    }
}
