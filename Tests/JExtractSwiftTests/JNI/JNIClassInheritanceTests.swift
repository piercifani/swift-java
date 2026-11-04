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

/// Swift subclasses become Java subclasses, and instances are wrapped in the Java class of their
/// dynamic type.
@Suite
struct JNIClassInheritanceTests {
  let source = """
    open class Animal {
      public init() {}
      open func sound() -> String { "" }
    }
    open class Dog: Animal {
      public override init() {}
      public func fetch() {}
    }
    public final class Puppy: Dog {}
    public final class Plain {}
    open class Lonely {}
    public func makeAnimal() -> Animal { Puppy() }
    """

  @Test
  func subclassExtendsItsSuperclass() throws {
    try assertOutput(
      input: source,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public class Animal implements JNISwiftInstance {",
        "public class Dog extends Animal {",
        "public final class Puppy extends Dog {",
      ]
    )
  }

  @Test
  func constructors() throws {
    try assertOutput(
      input: source,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "protected Animal(long selfPointer, SwiftArena swiftArena) {",
        """
        protected Dog(long selfPointer, SwiftArena swiftArena) {
          super(selfPointer, swiftArena);
        }
        """,
        """
        private Puppy(long selfPointer, SwiftArena swiftArena) {
          super(selfPointer, swiftArena);
        }
        """,
      ]
    )
  }

  @Test
  func wrappingDispatchesOnTheDynamicTypeDeepestFirst() throws {
    try assertOutput(
      input: source,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        public static Animal wrapMemoryAddressUnsafe(long selfPointer, SwiftArena swiftArena) {
          long dynamicType$ = Animal.$dynamicTypeMetadataAddress(selfPointer);
          if (dynamicType$ == Puppy.$typeMetadataAddressDowncall()) { return Puppy.wrapMemoryAddressUnsafe(selfPointer, swiftArena); }
          if (dynamicType$ == Dog.$typeMetadataAddressDowncall()) { return Dog.wrapMemoryAddressUnsafe(selfPointer, swiftArena); }
          return new Animal(selfPointer, swiftArena);
        }
        """,
        "private static native long $dynamicTypeMetadataAddress(long selfPointer);",
        // A subclass's metadata accessor is visible to its base classes.
        "static native long $typeMetadataAddressDowncall();",
      ]
    )
  }

  @Test
  func dynamicTypeThunk() throws {
    try assertOutput(
      input: source,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        let self$ = UnsafeMutablePointer<Animal>(bitPattern: Int(Int64(fromJNI: selfPointer, in: environment)))!
        let metadataPointer = unsafeBitCast(type(of: self$.pointee), to: UnsafeRawPointer.self)
        """
      ]
    )
  }

  @Test
  func openClassWithoutSubclassesIsExtendable() throws {
    try assertOutput(
      input: source,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public class Lonely implements JNISwiftInstance {",
        "protected Lonely(long selfPointer, SwiftArena swiftArena) {",
        """
        public static Lonely wrapMemoryAddressUnsafe(long selfPointer, SwiftArena swiftArena) {
          return new Lonely(selfPointer, swiftArena);
        }
        """,
      ]
    )
  }

  @Test
  func plainClassIsUnchanged() throws {
    try assertOutput(
      input: source,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public final class Plain implements JNISwiftInstance {",
        "private Plain(long selfPointer, SwiftArena swiftArena) {",
      ]
    )
  }
}
