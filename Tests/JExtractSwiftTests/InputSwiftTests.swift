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

import Foundation
import JExtractSwiftLib
import SwiftJavaConfigurationShared
import Testing

@Suite
struct InputSwiftTests {
  let fileManager = FileManager.default

  @Test(arguments: [JExtractGenerationMode.jni, .ffm])
  func loadSwiftinterface(mode: JExtractGenerationMode) throws {
    let tempDirectory: URL = fileManager.temporaryDirectory
      .appending(path: "loadSwiftinterface-\(UUID())")
    let outSwiftURL = tempDirectory.appending(path: "swift")
    let outJavaURL = tempDirectory.appending(path: "java")

    try withTemporaryFile(
      fileName: "MyDependent",
      extension: "swiftinterface",
      contents: """
        public struct Foo {}
        """,
      in: tempDirectory
    ) { swiftInterfaceURL in
      var config = Configuration()
      config.mode = mode
      config.javaPackage = "com.example"
      config.inputSwiftDirectory = swiftInterfaceURL.absoluteURL.path()
      config.swiftModule = "MySwift"
      config.outputSwiftDirectory = outSwiftURL.absoluteURL.path()
      config.outputJavaDirectory = outJavaURL.absoluteURL.path()

      try SwiftToJava(config: config, dependencyConfigs: [])
        .run()
    }

    let javaPackageRoot =
      outJavaURL
      .appending(path: "com")
      .appending(path: "example")
    let expectedSources: [URL] = [
      outSwiftURL.appending(path: "MySwiftModule+SwiftJava.swift"),
      outSwiftURL.appending(path: "MyDependent+SwiftJava.swift"),
      javaPackageRoot.appending(path: "Foo.java"),
      javaPackageRoot.appending(path: "MySwift.java"),
    ]

    for expectedSource in expectedSources {
      #expect(fileManager.fileExists(atPath: expectedSource.path()))
    }
  }

  @Test(arguments: [JExtractGenerationMode.jni, .ffm])
  func loadEmptySwiftinterface(mode: JExtractGenerationMode) throws {
    let tempDirectory: URL = fileManager.temporaryDirectory
      .appending(path: "loadEmptySwiftinterface-\(UUID())")
    let outSwiftURL = tempDirectory.appending(path: "swift")
    let outJavaURL = tempDirectory.appending(path: "java")

    try withTemporaryFile(
      fileName: "MyDependent",
      extension: "swiftinterface",
      contents: "",
      in: tempDirectory
    ) { swiftInterfaceURL in
      var config = Configuration()
      config.mode = mode
      config.writeEmptyFiles = true
      config.javaPackage = "com.example"
      config.inputSwiftDirectory = swiftInterfaceURL.absoluteURL.path()
      config.swiftModule = "MySwift"
      config.outputSwiftDirectory = outSwiftURL.absoluteURL.path()
      config.outputJavaDirectory = outJavaURL.absoluteURL.path()

      try SwiftToJava(config: config, dependencyConfigs: [])
        .run()
    }

    let javaPackageRoot =
      outJavaURL
      .appending(path: "com")
      .appending(path: "example")
    let expectedSources: [URL] = [
      outSwiftURL.appending(path: "MySwiftModule+SwiftJava.swift"),
      outSwiftURL.appending(path: "MyDependent+SwiftJava.swift"),
      javaPackageRoot.appending(path: "MySwift.java"),
    ]

    for expectedSource in expectedSources {
      #expect(fileManager.fileExists(atPath: expectedSource.path()))
    }
  }
}

extension InputSwiftTests {
  /// An extension of a dependency module's type, in a file named after neither: its thunks go in that
  /// file's output, the one a build expects, not in one named after the dependency's file.
  @Test(arguments: [JExtractGenerationMode.jni, .ffm])
  func extensionOfDependencyType(mode: JExtractGenerationMode) throws {
    let tempDirectory: URL = fileManager.temporaryDirectory
      .appending(path: "extensionOfDependencyType-\(UUID())")
    let dependencyDirectory = tempDirectory.appending(path: "DependencyLib")
    let inputDirectory = tempDirectory.appending(path: "PrimaryLib")
    let outSwiftURL = tempDirectory.appending(path: "swift")
    try fileManager.createDirectory(at: dependencyDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
    try """
    public struct Payload {
      public let value: Int32
      public init(value: Int32) { self.value = value }
    }
    """.write(to: dependencyDirectory.appending(path: "Payload.swift"), atomically: true, encoding: .utf8)
    try """
    import DependencyLib

    extension Payload {
      public func doubled() -> Int32 { value * 2 }
    }
    """.write(to: inputDirectory.appending(path: "Payload+Doubling.swift"), atomically: true, encoding: .utf8)

    var dependency = Configuration()
    dependency.javaPackage = "com.example.dep"
    var config = Configuration()
    config.mode = mode
    config.javaPackage = "com.example"
    config.inputSwiftDirectory = inputDirectory.path()
    config.swiftModule = "PrimaryLib"
    config.outputSwiftDirectory = outSwiftURL.path()
    config.outputJavaDirectory = tempDirectory.appending(path: "java").path()

    try SwiftToJava(
      config: config,
      dependencyConfigs: [
        DependencyConfig(swiftModuleName: "DependencyLib", configuration: dependency, swiftSourcePaths: [dependencyDirectory])
      ]
    ).run()

    let thunks = try String(contentsOf: outSwiftURL.appending(path: "Payload+Doubling+SwiftJava.swift"), encoding: .utf8)
    #expect(thunks.contains("doubled"))
    #expect(!fileManager.fileExists(atPath: outSwiftURL.appending(path: "Payload+SwiftJava.swift").path()))
  }
}
