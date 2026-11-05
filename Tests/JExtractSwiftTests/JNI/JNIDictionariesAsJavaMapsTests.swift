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

/// `dictionariesAsJavaMaps`: dictionaries cross as `java.util.Map` copies and `Any` as `Object`.
@Suite
struct JNIDictionariesAsJavaMapsTests {
  var config: Configuration {
    var config = Configuration()
    config.dictionariesAsJavaMaps = true
    return config
  }

  let input = """
    public struct Message {
      public init(metadata: [String: String]?) {}
      public var metadata: [String: String]? { nil }
      public var properties: [String: Any?]? { nil }
    }
    public func track(event: String, properties: [String: Any]) {}
    public func setAttribute(key: String, value: Any) {}
    public func isPush(_ userInfo: [AnyHashable: Any]) -> Bool { true }
    public func counts() -> [String: [String: Int64]] { [:] }
    public enum Input {
      case close(metadata: [String: String]?)
      case log(name: String, values: [String: Any]?)
    }
    """

  @Test
  func dictionariesAndAny_areJavaMapsAndObjects() throws {
    try assertOutput(
      input: input,
      config: config,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public static Message init(java.util.Map<java.lang.String, java.lang.String> metadata, SwiftArena swiftArena)",
        "public java.util.Map<java.lang.String, java.lang.String> getMetadata()",
        "public java.util.Map<java.lang.String, java.lang.Object> getProperties()",
        "public static void track(java.lang.String event, java.util.Map<java.lang.String, java.lang.Object> properties)",
        "public static void setAttribute(java.lang.String key, java.lang.Object value)",
        "public static boolean isPush(java.util.Map<java.lang.Object, java.lang.Object> userInfo)",
        "public static java.util.Map<java.lang.String, java.util.Map<java.lang.String, java.lang.Long>> counts()",
        "record Close(java.util.Map<java.lang.String, java.lang.String> metadata) implements Case {}",
        "record Log(java.lang.String name, java.util.Map<java.lang.String, java.lang.Object> values) implements Case {}",
      ],
      notExpectedChunks: ["SwiftDictionaryMap"]
    )
    try assertOutput(
      input: input,
      config: config,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "NullableBridge<MapBridge<JavaBoxableBridge<String>, JavaBoxableBridge<String>>>.fromJavaObject(metadata, in: environment)",
        "NullableBridge<MapBridge<JavaBoxableBridge<String>, NullableBridge<AnyBridge>>>.toJavaObject(",
        "MapBridge<JavaBoxableBridge<String>, AnyBridge>.fromJavaObject(properties, in: environment)",
        "AnyBridge.fromJavaObject(value, in: environment)",
        "MapBridge<AnyHashableBridge, AnyBridge>.fromJavaObject(userInfo, in: environment)",
        "MapBridge<JavaBoxableBridge<String>, MapBridge<JavaBoxableBridge<String>, JavaBoxableBridge<Int64>>>.toJavaObject(",
      ]
    )
  }

  @Test
  func javaImplementations_takeAndReturnJavaMaps() throws {
    var config = config
    config.enableJavaCallbacks = true
    config.javaCallbacksBindings = .jextract
    let input = """
      public protocol Analytics {
        func track(event: String, properties: [String: Any])
        func isPush(_ userInfo: [AnyHashable: Any]) -> Bool
        func attributes() -> [String: String]?
        func observeAll(onChange: @escaping ([String: Int64]) -> Void)
      }
      public func onMetadata(_ cb: @escaping ([String: String]?) -> Void) {}
      """
    try assertOutput(
      input: input,
      config: config,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "void track(java.lang.String event, java.util.Map<java.lang.String, java.lang.Object> properties);",
        "boolean isPush(java.util.Map<java.lang.Object, java.lang.Object> userInfo);",
        "java.util.Map<java.lang.String, java.lang.String> attributes();",
        "void apply(java.util.Map<java.lang.String, java.lang.Long> _0);",
        "void apply(java.util.Map<java.lang.String, java.lang.String> _0);",
      ]
    )
    try assertOutput(
      input: input,
      config: config,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "_javaObjectWrapper(properties, bridge: MapBridge<JavaBoxableBridge<String>, AnyBridge>.self)",
        "_javaObjectWrapper(userInfo, bridge: MapBridge<AnyHashableBridge, AnyBridge>.self)",
        "_swiftValue(of: ",
        "javaInterface_onChange$.apply(_javaObjectWrapper(_0, bridge: MapBridge<JavaBoxableBridge<String>, JavaBoxableBridge<Int64>>.self))",
        "_javaObjectWrapper(_0, bridge: NullableBridge<MapBridge<JavaBoxableBridge<String>, JavaBoxableBridge<String>>>.self)",
      ]
    )
  }
}
