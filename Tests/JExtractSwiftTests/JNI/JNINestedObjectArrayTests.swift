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

import JExtractSwiftLib
import SwiftJavaConfigurationShared
import Testing

/// Arrays of arrays of jextracted types cross as `long[][]` of memory addresses.
@Suite
struct JNINestedObjectArrayTests {
  let source =
    """
    public struct Item {}

    public func sections(_ items: [Item]) -> [[Item]] { [items] }
    public func count(_ sections: [[Item]]) -> Int { sections.count }
    """

  @Test
  func javaBindings() throws {
    try assertOutput(
      input: source,
      .jni,
      .java,
      expectedChunks: [
        "public static Item[][] sections(Item[] items, SwiftArena swiftArena) {",
        "private static native long[][] $sections(long[] items);",
        "return Arrays.stream(row).mapToObj((pointer) -> {",
        ").toArray(Item[][]::new);",
        "public static long count(Item[][] sections) {",
        "return Arrays.stream(Objects.requireNonNull(row, \"sections must not be null\")).mapToLong(Item::$memoryAddress).toArray();",
        ").toArray(long[][]::new));",
        "private static native long $count(long[][] sections);",
      ]
    )
  }

  @Test
  func swiftThunks() throws {
    try assertOutput(
      input: source,
      .jni,
      .swift,
      expectedChunks: [
        "[[Int64]](fromJNI: sections, in: environment).map( { (pointer2$) in",
        "return pointer2$.map( { (pointer1$) in",
      ]
    )
  }
}
