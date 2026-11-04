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
import SwiftExtract
import SwiftJavaConfigurationShared
import Testing

@Suite
struct JNICodegenFixesTests {
  // MARK: `(Int) -> Int` closures

  @Test
  func intClosure_interfaceIsPrinted() throws {
    try assertOutput(
      input: "public func apply(_ f: (Int) -> Int, to x: Int) -> Int { f(x) }",
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        public static class apply {
          private apply() {}
          /** Corresponds to the Swift closure parameter of type {@code (Int) -> Int}. */
          @FunctionalInterface
          public interface f {
            long apply(long _0);
          }
        }
        """,
        "public static long apply(com.example.swift.SwiftModule.apply.f f, long x)",
      ]
    )
  }

  @Test
  func intClosure_upcallCallsTheInterfaceMethod() throws {
    try assertOutput(
      input: "public func apply(_ f: (Int) -> Int, to x: Int) -> Int { f(x) }",
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        #"let methodID$ = environment.interface.GetMethodID(environment, class$, "apply", "(J)J")!"#
      ],
      notExpectedChunks: [
        "applyAsLong"
      ]
    )
  }

  @Test
  func intClosure_widensForThirtyTwoBitPlatforms() throws {
    try assertOutput(
      input: "public func apply(_ f: (Int) -> Int, to x: Int) -> Int { f(x) }",
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "let arguments$: [jvalue] = [Int64(_0).getJValue(in: environment)]",
        "return Int(Int64(fromJNI: environment.interface.CallLongMethodA(environment, f, methodID$, arguments$), in: environment))",
      ]
    )
  }

  @Test
  func int64Closure_stillUsesTheKnownInterface() throws {
    try assertOutput(
      input: "public func apply(_ f: (Int64) -> Int64, to x: Int64) -> Int64 { f(x) }",
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public static long apply(java.util.function.LongUnaryOperator f, long x)"
      ]
    )
  }

  // MARK: `inout`

  @Test
  func inoutParameter_isSkippedAndReported() throws {
    let generator = try generate("public func bump(_ x: inout Int64) {}")
    #expect(generator.skippedDeclarations.count == 1, "\(generator.skippedDeclarations)")
    #expect(generator.skippedDeclarations.first?.hasPrefix("bump(_:): inoutParametersNotSupported") == true)
  }

  // MARK: Unannotated variables

  @Test
  func unannotatedLiterals_areInferred() throws {
    try assertOutput(
      input: """
        public enum Constants {
          public static let answer = 42
          public static let below = -1
          public static let ratio = 1.5
          public static let title = "Hello"
          public static let enabled = true
        }
        """,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public static long getAnswer() {",
        "public static long getBelow() {",
        "public static double getRatio() {",
        "public static java.lang.String getTitle() {",
        "public static boolean isEnabled() {",
      ]
    )
  }

  @Test
  func unannotatedInitializerCall_isInferred() throws {
    try assertOutput(
      input: """
        public struct Item {
          public init() {}
          public struct Detail {
            public init() {}
          }
        }
        public final class Holder {
          public var item = Item()
          public var detail = Item.Detail()
        }
        """,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public Item getItem(SwiftArena swiftArena) {",
        "public Item.Detail getDetail(SwiftArena swiftArena) {",
      ]
    )
  }

  @Test
  func ambiguousInitializers_stillNeedAnAnnotation() throws {
    let sink = SkippedDeclarationCollector()
    _ = try generate(
      """
      public struct Item {
        public static func make() -> Item { Item() }
        public static let shared: Item = Item()
      }
      public func makeItem() -> Item { Item() }
      public final class Holder {
        public var made = Item.make()
        public var fromFunction = makeItem()
        public var member = Item.shared
      }
      """,
      sink: sink
    )
    let skipped = sink.skipped.map { String($0.prefix { $0 != ":" }) }.sorted()
    #expect(skipped == ["Holder.fromFunction", "Holder.made", "Holder.member"], "\(sink.skipped)")
  }

  private func generate(_ source: String, sink: SkippedDeclarationCollector? = nil) throws -> JNISwift2JavaGenerator {
    var config = Configuration()
    config.swiftModule = "SwiftModule"
    let translator = makeSwiftJavaAnalyzer(config: config, diagnosticsSink: sink)
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
    var swiftPrinter = SwiftPrinter(mode: .accumulateAll)
    try generator.writeSwiftThunkSources(&swiftPrinter)
    return generator
  }
}
