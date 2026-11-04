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

/// Escaping closures whose parameters are jextracted types, and closure types
/// carrying `@Sendable` / `@MainActor`.
@Suite
struct JNIEscapingClosureJExtractedTypesTests {
  let itemSource =
    """
    public struct Item {
      public var id: String
    }
    """

  @Test
  func structParameter_interfaceUsesJavaClass() throws {
    try assertOutput(
      input: itemSource + "\npublic func setHandler(_ handler: @escaping (Item) -> Void) {}",
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        @JavaInterface("com.example.swift.SwiftModule$setHandler$handler")
        public struct JavaSwiftModule_setHandler_handler {
          @JavaMethod
          public func apply(_ _0: JavaItem?)
        }
        """
      ]
    )
  }

  @Test
  func structParameter_minimalJavaClassWrapperWithoutCallbacks() throws {
    try assertOutput(
      input: itemSource + "\npublic func setHandler(_ handler: @escaping (Item) -> Void) {}",
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        @JavaClass("com.example.swift.Item")
        open class JavaItem: JavaObject {}
        """,
        """
        extension JavaClass<JavaItem> {
          @JavaStaticMethod
          public func wrapMemoryAddressUnsafe(_ selfPointer: Int64) -> JavaItem!
        }
        """,
      ]
    )
  }

  @Test
  func structParameter_conversionIsInsideTheClosure() throws {
    try assertOutput(
      input: itemSource + "\npublic func setHandler(_ handler: @escaping (Item) -> Void) {}",
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        return { _0 in
        let _0Class = try! JavaClass<JavaItem>(environment: JavaVirtualMachine.shared().environment())
        let _0Pointer = UnsafeMutablePointer<Item>.allocate(capacity: 1)
        _0Pointer.initialize(to: _0)
        javaInterface_handler$.apply(_0Class.wrapMemoryAddressUnsafe(Int64(Int(bitPattern: _0Pointer))))
        }
        """
      ]
    )
  }

  @Test
  func nonEscapingStructClosure_usesTheEscapingLowering() throws {
    try assertOutput(
      input: itemSource + "\npublic func transform(_ item: Item, _ f: (Item) -> Item) -> Item { f(item) }",
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        @JavaInterface("com.example.swift.SwiftModule$transform$f")
        public struct JavaSwiftModule_transform_f {
          @JavaMethod
          public func apply(_ _0: JavaItem?) -> JavaItem!
        }
        """,
        // Spelled out: inferred from the non-escaping parameter, the returned closure couldn't escape.
        """
        result$.initialize(to: SwiftModule.transform(item$.pointee, { () -> (Item) -> Item in
        guard let f else {
          fatalError("f is null")
        }
        let javaInterface_f$ = JavaSwiftModule_transform_f(javaThis: f, environment: environment)
        return { _0 in
        """,
      ]
    )
  }

  @Test
  func nonEscapingStructClosure_javaInterface() throws {
    try assertOutput(
      input: itemSource + "\npublic func transform(_ item: Item, _ f: (Item) -> Item) -> Item { f(item) }",
      .jni,
      .java,
      detectChunkByInitialLines: 2,
      expectedChunks: [
        """
        @FunctionalInterface
        public interface f {
          Item apply(Item _0);
        }
        """
      ]
    )
  }

  @Test
  func optionalStructParameter_isJavaOptional() throws {
    try assertOutput(
      input: itemSource + "\npublic func check(_ cb: @escaping (String, Item?) -> Bool) {}",
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        @JavaInterface("com.example.swift.SwiftModule$check$cb")
        public struct JavaSwiftModule_check_cb {
          @JavaMethod
          public func apply(_ _0: String, _ _1: JavaOptional<JavaItem>?) -> Bool
        }
        """
      ]
    )
  }

  @Test
  func sendableMainActorClosure_isTranslated() throws {
    try assertOutput(
      input: itemSource + "\npublic func onOpen(_ cb: @escaping @MainActor @Sendable (Item) -> Void) {}",
      .jni,
      .java,
      detectChunkByInitialLines: 2,
      expectedChunks: [
        """
        /** Corresponds to the Swift closure parameter of type {@code @escaping @Sendable @MainActor (Item) -> Void}. */
        @FunctionalInterface
        public interface cb {
          void apply(Item _0);
        }
        """
      ]
    )
  }

  @Test
  func sendableClosure_usesTheCallingThreadsEnvironment() throws {
    try assertOutput(
      input: "public func deliver(_ cb: @escaping @Sendable (Int64) -> Void) {}",
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        nonisolated(unsafe) let javaInterface_cb$ = JavaSwiftModule_deliver_cb(javaThis: cb, environment: environment)
        """,
        """
        let javaInterface_cb$call = JavaSwiftModule_deliver_cb(javaThis: javaInterface_cb$.javaThis, environment: try! JavaVirtualMachine.shared().environment())
        """,
      ]
    )
  }

  @Test
  func closureProperty_setterIsEscaping() throws {
    try assertOutput(
      input:
        """
        public struct Callbacks {
          public var onClose: @MainActor @Sendable () -> Void
        }
        """,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        @JavaInterface("com.example.swift.Callbacks$setOnClose$newValue")
        """
      ]
    )
  }

  @Test
  func closureReturningTypeFromDependencyModule_swiftThunks() throws {
    try assertOutput(
      input: """
        import DependencyLib

        public func configure(scheme: @escaping () -> DependencyScheme) {}
        """,
      .jni,
      .swift,
      swiftModuleName: "PrimaryLib",
      dependencySwiftSources: ["DependencyLib": "public struct DependencyScheme {}"],
      moduleJavaPackages: ["DependencyLib": "com.example.dep"],
      expectedChunks: [
        "public func apply() -> JavaDependencyScheme!",
        #"@JavaClass("com.example.dep.DependencyScheme")"#,
      ]
    )
  }

  /// A `@MainActor` closure may run on another thread than the one that created it, like a `@Sendable` one.
  @Test
  func mainActorClosure_wrapsJavaObjectPerThread() throws {
    try assertOutput(
      input: "public func onTap(_ cb: @escaping @MainActor () -> Void) {}",
      .jni,
      .swift,
      expectedChunks: [
        "nonisolated(unsafe) let javaInterface_cb$ = JavaSwiftModule_onTap_cb(javaThis: cb, environment: environment)",
        "let javaInterface_cb$ = JavaSwiftModule_onTap_cb(javaThis: javaInterface_cb$.javaThis, environment: try! JavaVirtualMachine.shared().environment())",
      ]
    )
  }

  @Test
  func mainActorClosureTypealiasFromDependency_wrapsJavaObjectPerThread() throws {
    try assertOutput(
      input: """
        import DependencyLib

        public func onLogin(_ didLogin: @escaping VoidCallback) {}
        """,
      .jni,
      .swift,
      swiftModuleName: "PrimaryLib",
      dependencySwiftSources: ["DependencyLib": "public typealias VoidCallback = @MainActor () -> Void"],
      moduleJavaPackages: ["DependencyLib": "com.example.dep"],
      expectedChunks: [
        "nonisolated(unsafe) let javaInterface_didLogin$ = JavaPrimaryLib_onLogin_didLogin(javaThis: didLogin, environment: environment)"
      ]
    )
  }

  @Test
  func closureTakingArrayOfJextractedType_printsItsJavaClass() throws {
    try assertOutput(
      input: itemSource + "\npublic func onSelect(_ cb: @escaping ([Item]) -> Void) {}",
      .jni,
      .swift,
      expectedChunks: [
        #"@JavaClass("com.example.swift.Item")"#,
        "public func apply(_ _0: [JavaItem?])",
      ]
    )
  }
}
