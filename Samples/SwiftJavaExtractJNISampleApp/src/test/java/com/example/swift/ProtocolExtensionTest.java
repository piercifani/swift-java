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

package com.example.swift;

import org.junit.jupiter.api.Test;
import org.swift.swiftkit.core.SwiftArena;

import static org.junit.jupiter.api.Assertions.*;

public class ProtocolExtensionTest {
    @Test
    void conformerGetsExtensionMembers() {
        try (var arena = SwiftArena.ofConfined()) {
            Labeled item = LabeledItem.init("a", arena);
            assertEquals("untitled a", item.getTitle());   // requirement implemented by the extension
            assertEquals("a::uid", item.uid());            // method the extension adds
        }
    }

    @Test
    void conformerKeepsItsOwnImplementation() {
        try (var arena = SwiftArena.ofConfined()) {
            Labeled item = TitledItem.init("b", "Markets", arena);
            assertEquals("Markets", item.getTitle());
            assertEquals("b::uid", item.uid());
        }
    }
}
