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

class ClassHierarchyTest {
    @Test
    fun subclassIsASuperclass() {
        val dog = Dog.init("Rex")
        val animal: Animal = dog
        assertEquals("Rex says woof", animal.describe())
        assertEquals("Rex", animal.name)
        assertEquals("stick", dog.fetch())
    }

    @Test
    fun subclassPassedAsSuperclass() {
        assertEquals("Rex says woof", Zoo.describe(Dog.init("Rex")))
    }

    @Test
    fun returnedInstanceKeepsItsDynamicClass() {
        val animal = Zoo.makeDog("Rex")
        assertIs<Dog>(animal)
        assertEquals("stick", animal.fetch())
    }
}
