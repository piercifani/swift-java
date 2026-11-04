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

/// Declarations jextract skips are reported, and `failOnSkippedDeclarations` turns them into a failure.
@Suite
struct JNISkippedDeclarationsTests {
  let source =
    """
    public struct Tag {
      public var name: String
    }
    public func supported() -> Tag { fatalError() }
    public func sparse() -> [Tag?] { [] }
    public func nested() -> [[String: Int64]] { [] }
    """

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

  @Test
  func translationFailuresAreRecordedOnce() throws {
    let generator = try generate(source)
    let skipped = generator.skippedDeclarations.sorted()
    #expect(skipped.count == 2, "\(skipped)")
    #expect(skipped[0].hasPrefix("nested()"))
    #expect(skipped[1].hasPrefix("sparse()"))
  }

  @Test
  func analysisSkipsAreCollected() throws {
    let sink = SkippedDeclarationCollector()
    // `S.make()` can't be typed without the type checker, so it still needs an annotation.
    _ = try generate(
      "public struct S { public static func make() -> S { S() }; public static let untyped = S.make() }",
      sink: sink
    )
    #expect(sink.skipped.count == 1, "\(sink.skipped)")
    #expect(sink.skipped.first?.hasPrefix("S.untyped") == true)
  }

  @Test
  func failsOnlyWhenConfigured() throws {
    let skipped = ["sparse(): unsupported"]
    var config = Configuration()
    let log = Logger(label: "test", logLevel: .critical)

    #expect(throws: Never.self) {
      try SwiftToJava(config: config, dependencyConfigs: []).failIfSkipped(skipped, module: "M", log: log)
    }

    config.failOnSkippedDeclarations = true
    let error = #expect(throws: SkippedDeclarationsError.self) {
      try SwiftToJava(config: config, dependencyConfigs: []).failIfSkipped(skipped, module: "M", log: log)
    }
    #expect(error?.description.contains("  - sparse(): unsupported") == true)
    #expect(throws: Never.self) {
      try SwiftToJava(config: config, dependencyConfigs: []).failIfSkipped([], module: "M", log: log)
    }
  }
}
