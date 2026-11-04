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
import Testing

/// Arrays of optionals, dictionaries and sets are converted element by element with `ArrayBridge`.
@Suite
struct JNIBridgedArrayElementsTests {
  @Test
  func optionalElements_java() throws {
    try assertOutput(
      input: "public func f(array: [Int64?]) -> [Int64?] {}",
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        public static java.util.Optional<java.lang.Long>[] f(java.util.Optional<java.lang.Long>[] array) {
          return (java.util.Optional<java.lang.Long>[]) SwiftModule.$f(Objects.requireNonNull(array, "array must not be null"));
        }
        """,
        "private static native java.lang.Object[] $f(java.lang.Object[] array);",
      ]
    )
  }

  @Test
  func optionalElements_swift() throws {
    try assertOutput(
      input: "public func f(array: [Int64?]) -> [Int64?] {}",
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "return ArrayBridge<OptionalBridge<JavaBoxableBridge<Int64>>>.toJavaObject(SwiftModule.f(array: ArrayBridge<OptionalBridge<JavaBoxableBridge<Int64>>>.fromJavaObject(array, in: environment)), in: environment)"
      ]
    )
  }

  @Test
  func dictionaryElements_java() throws {
    try assertOutput(
      input: "public func f() -> [[String: Int64]] {}",
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        public static org.swift.swiftkit.core.collections.SwiftDictionaryMap<java.lang.String, java.lang.Long>[] f() {
          return (org.swift.swiftkit.core.collections.SwiftDictionaryMap<java.lang.String, java.lang.Long>[]) SwiftModule.$f();
        }
        """
      ]
    )
  }

  @Test
  func jextractedOptionalElements_java() throws {
    try assertOutput(
      input: """
        public struct Tag {}
        public func f() -> [Tag?] {}
        """,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public static java.util.Optional<Tag>[] f() {"
      ]
    )
  }
}
