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

/// Functions returning `AsyncStream<T>` or `AsyncThrowingStream<T, _>` return a `SwiftAsyncStream<T>` to Java.
@Suite
struct JNIAsyncStreamTests {
  @Test
  func javaReturnsSwiftAsyncStream() throws {
    try assertOutput(
      input: "public func ticks(count: Int64) -> AsyncStream<Int64> { fatalError() }",
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        public static org.swift.swiftkit.core.SwiftAsyncStream<java.lang.Long> ticks(long count) {
          org.swift.swiftkit.core.SwiftAsyncStream<java.lang.Long> stream$ = new org.swift.swiftkit.core.SwiftAsyncStream<java.lang.Long>();
          SwiftModule.$ticks(count, stream$);
          return stream$.map((element$) -> {
            return element$;
          }
          );
        }
        """,
        "private static native void $ticks(long count, org.swift.swiftkit.core.SwiftAsyncStream<java.lang.Long> result_stream);",
      ]
    )
  }

  @Test
  func swiftAttachesTheStreamWithAnElementConverter() throws {
    try assertOutput(
      input: "public func ticks(count: Int64) -> AsyncStream<Int64> { fatalError() }",
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        SwiftJavaRuntimeSupport._attachAsyncStream(SwiftModule.ticks(count: Int64(fromJNI: count, in: environment)), to: result_stream, environment: environment) { element$, environment in
        return SwiftJavaRuntimeSupport._JNIBoxedConversions.box(element$.getJNILocalRefValue(in: environment), in: environment)
        }
        """
      ]
    )
  }

  @Test(arguments: ["Error", "any Error"])
  func throwingStreamsAreAttachedLikeStreams(failure: String) throws {
    let input = "public func ticks(count: Int64) -> AsyncThrowingStream<Int64, \(failure)> { fatalError() }"
    try assertOutput(
      input: input,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public static org.swift.swiftkit.core.SwiftAsyncStream<java.lang.Long> ticks(long count) {",
        "private static native void $ticks(long count, org.swift.swiftkit.core.SwiftAsyncStream<java.lang.Long> result_stream);",
      ]
    )
    try assertOutput(
      input: input,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "SwiftJavaRuntimeSupport._attachAsyncStream(SwiftModule.ticks(count: Int64(fromJNI: count, in: environment)), to: result_stream, environment: environment) { element$, environment in"
      ]
    )
  }

  @Test
  func jextractedElementsAreMappedToTheirJavaClass() throws {
    try assertOutput(
      input: """
        public struct Tick {}
        public func ticks() -> AsyncStream<Tick> { fatalError() }
        """,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public static org.swift.swiftkit.core.SwiftAsyncStream<Tick> ticks(SwiftArena swiftArena) {",
        "return Tick.wrapMemoryAddressUnsafe(element$, swiftArena);",
      ]
    )
  }

  @Test
  func unsupportedStreamsAreSkipped() throws {
    var config = Configuration()
    config.swiftModule = "SwiftModule"
    let translator = makeSwiftJavaAnalyzer(config: config)
    try translator.analyze(
      path: "/fake/Fake.swiftinterface",
      text: """
        public func later() async -> AsyncStream<Int64> { fatalError() }
        public func pairs() -> AsyncStream<(Int64, String)> { fatalError() }
        """
    )
    let generator = JNISwift2JavaGenerator(
      config: config,
      translator: translator,
      javaPackage: "com.example.swift",
      swiftOutputDirectory: "/fake",
      javaOutputDirectory: "/fake",
      javaClassLookupTable: [:],
      moduleJavaPackages: [:]
    )
    var printer = JavaPrinter(mode: .accumulateAll)
    try generator.writeExportedJavaSources(&printer)
    let skipped = generator.skippedDeclarations.map { String($0.prefix { $0 != ":" }) }.sorted()
    #expect(skipped == ["later()", "pairs()"], "\(generator.skippedDeclarations)")
  }
}
