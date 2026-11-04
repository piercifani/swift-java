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
import kotlin.test.assertIs
import kotlin.test.assertNotEquals
import kotlin.test.assertNotSame

// Kotlin compares objects with `==` (equals) and collections hash them: two wrappers of one Swift
// instance must be equal, as Compose relies on to skip recomposition.
class IdentityTest {
    @Test
    fun wrappersOfTheSameInstanceAreEqual() {
        val first = Session.getShared()
        val second = Session.getShared()
        assertNotSame(first, second)
        assertEquals(first, second)
        assertEquals(1, setOf(first, second, Session.echo(first)).size)
        assertNotEquals(first, Session.init("other"))
    }

    @Test
    fun sameInstanceThroughItsSuperclassType() {
        val dog = Dog.init("Rex")
        val back: Animal = Echo.animal(dog)
        assertNotSame<Animal>(dog, back)
        assertEquals<Animal>(dog, back)
        assertEquals(dog.hashCode(), back.hashCode())
        assertNotEquals<Animal>(dog, Dog.init("Rex"))
    }

    @Test
    fun enumCaseWithoutAnArena() {
        val case = Store.init().route(Item.init("a", 1)).case
        assertIs<Route.Case.Detail>(case)
        assertEquals("a", case.arg0.id)
    }
}
