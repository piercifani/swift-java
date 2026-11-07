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
import CodePrinting
import JExtractSwiftLib
import SwiftJavaConfigurationShared
import Testing

/// Closures returned to Java: a lambda of the closure's functional interface over a `SwiftClosure`.
@Suite
struct JNIClosureResultsTests {
  let source =
    """
    public struct Item {
      public var id: String
    }
    public final class Notifier {
      public var onItem: ((Item) -> Void)?
      public let format: (Item, Int64) -> String
      public func makeFormatter(prefix: String) -> (Item) -> String {}
    }
    """

  @Test
  func functionResult_javaLambda() throws {
    try assertOutput(
      input: source,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        public com.example.swift.Notifier.makeFormatter.result makeFormatter(java.lang.String prefix) {
          org.swift.swiftkit.core.SwiftClosure closure$ = new org.swift.swiftkit.core.SwiftClosure(Notifier.$makeFormatter(prefix, this.$memoryAddress()));
          return (com.example.swift.Notifier.makeFormatter.result) (Item closure$0) -> (java.lang.String) closure$.call(closure$0);
        }
        """,
        "private static native long $makeFormatter(java.lang.String prefix, long selfPointer);",
        """
        @FunctionalInterface
        public interface result {
          java.lang.String apply(Item _0);

          default java.lang.String invoke(Item _0) {
            return apply(_0);
          }
        }
        """,
      ]
    )
  }

  @Test
  func functionResult_swiftClosureHandle() throws {
    try assertOutput(
      input: source,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        let closure$ = selfPointer$.pointee.makeFormatter(prefix: String(fromJNI: prefix, in: environment))
        return _makeSwiftClosure { arguments$, environment in
          return JavaBoxableBridge<String>.toJavaObject(closure$(_JNIBridge_Item.fromJavaObject(_swiftClosureArgument(arguments$, 0, in: environment), in: environment)), in: environment)
        }
        """
      ]
    )
  }

  @Test
  func settableProperty_getterReturnsTheSetterInterface() throws {
    try assertOutput(
      input: source,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public java.util.Optional<com.example.swift.Notifier.setOnItem.newValue> getOnItem() {",
        "long closure$handle = Notifier.$getOnItem(this.$memoryAddress());",
        "return java.util.Optional.ofNullable(closure$ == null ? null : (com.example.swift.Notifier.setOnItem.newValue) (Item closure$0) -> closure$.call(closure$0));",
        "public void setOnItem(java.util.Optional<com.example.swift.Notifier.setOnItem.newValue> newValue) {",
        "Notifier.$setOnItem(newValue.orElse(null), this.$memoryAddress());",
      ]
    )
  }

  @Test
  func settableProperty_nullableHelperClassPrintedOnce() throws {
    var config = Configuration()
    config.swiftModule = "SwiftModule"
    config.optionalsAsNullable = true
    try assertOutput(
      input: source,
      config: config,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public com.example.swift.Notifier.setOnItem.newValue getOnItem() {",
        "return closure$ == null ? null : (com.example.swift.Notifier.setOnItem.newValue) (Item closure$0) -> closure$.call(closure$0);",
        "public void setOnItem(com.example.swift.Notifier.setOnItem.newValue newValue) {",
      ]
    )
    let translator = makeSwiftJavaAnalyzer(config: config)
    try translator.analyze(path: "/fake/Fake.swiftinterface", text: source)
    let generator = JNISwift2JavaGenerator(
      config: config,
      translator: translator,
      javaPackage: "com.example.swift",
      swiftOutputDirectory: "/fake",
      javaOutputDirectory: "/fake",
      javaClassLookupTable: [:],
      moduleJavaPackages: [:]
    )
    var javaPrinter = JavaPrinter(mode: .accumulateAll)
    try generator.writeExportedJavaSources(&javaPrinter)
    // The getter and the setter share it.
    #expect(javaPrinter.contents.components(separatedBy: "public static class setOnItem").count == 2)
  }

  @Test
  func optionalClosureParameter_nilOrEscapingClosure() throws {
    try assertOutput(
      input: source,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "selfPointer$.pointee.onItem = newValue == nil ? nil : {",
        "return closure$.map { closure$ in _makeSwiftClosure { arguments$, environment in",
      ]
    )
  }

  @Test
  func readOnlyProperty_ownInterface() throws {
    try assertOutput(
      input: source,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public com.example.swift.Notifier.getFormat.result getFormat() {",
        "return (com.example.swift.Notifier.getFormat.result) (Item closure$0, long closure$1) -> (java.lang.String) closure$.call(closure$0, closure$1);",
      ]
    )
  }

  @Test
  func mainActorClosureResult_runsOnTheMainActor() throws {
    try assertOutput(
      input: "public func makeHandler() -> @MainActor (String) -> Int64 {}",
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        return _makeMainActorSwiftClosure { arguments$, environment in
          nonisolated(unsafe) let callee$ = closure$
          return JavaBoxableBridge<Int64>.toJavaObject(callee$(JavaBoxableBridge<String>.fromJavaObject(_swiftClosureArgument(arguments$, 0, in: environment), in: environment)), in: environment)
        }
        """
      ]
    )
  }

  @Test
  func asyncClosureResult_returnsAFuture() throws {
    try assertOutput(
      input: "public func makeLoader() -> @MainActor (String) async throws -> Int64 {}",
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        return _makeSwiftClosure { arguments$, environment in
          nonisolated(unsafe) let callee$ = closure$
          nonisolated(unsafe) let argument0$ = JavaBoxableBridge<String>.fromJavaObject(_swiftClosureArgument(arguments$, 0, in: environment), in: environment)
          return _swiftClosureFuture(in: environment) { environment in
            return JavaBoxableBridge<Int64>.toJavaObject(try await callee$(argument0$), in: environment)
          }
        }
        """
      ]
    )
  }

  @Test
  func throwingClosureResult_isSkipped() throws {
    try assertOutput(
      input: "public func makeHandler() -> () throws -> Void {}",
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [],
      notExpectedChunks: ["makeHandler()"]
    )
  }
}
