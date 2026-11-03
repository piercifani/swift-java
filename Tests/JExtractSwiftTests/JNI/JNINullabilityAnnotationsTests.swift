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

/// `nullableAnnotation` and `nonNullAnnotation` give Kotlin nullable and non-null types instead of platform types.
@Suite
struct JNINullabilityAnnotationsTests {
  func config(optionalsAsNullable: Bool) -> Configuration {
    var config = Configuration()
    config.optionalsAsNullable = optionalsAsNullable
    config.nullableAnnotation = "androidx.annotation.Nullable"
    config.nonNullAnnotation = "androidx.annotation.NonNull"
    return config
  }

  let source =
    """
    public struct Item {
      public var note: String?
    }
    public func find(name: String, limit: Int64, tag: String?) -> Item? {}
    public func load() async -> String {}
    public func invert(_ flag: Bool?) -> Bool? {}
    """

  @Test
  func parametersAndResults() throws {
    try assertOutput(
      input: source,
      config: config(optionalsAsNullable: true),
      .jni,
      .java,
      detectChunkByInitialLines: 2,
      expectedChunks: [
        "import androidx.annotation.Nullable;",
        "import androidx.annotation.NonNull;",
        // Primitives aren't annotated.
        """
        @Nullable
        public static Item find(@NonNull java.lang.String name, long limit, @Nullable String tag, SwiftArena swiftArena) {
        """,
        // An async result is a future, never `null`.
        """
        @NonNull
        public static java.util.concurrent.CompletableFuture<java.lang.String> load() {
        """,
        """
        @Nullable
        public String getNote() {
        """,
        "public void setNote(@Nullable String newValue) {",
        // Packed with its discriminator into one native result.
        """
        @Nullable
        public static Boolean invert(@Nullable Boolean flag) {
        """,
      ]
    )
  }

  @Test
  func javaOptionalsAreNonNull() throws {
    try assertOutput(
      input: source,
      config: config(optionalsAsNullable: false),
      .jni,
      .java,
      detectChunkByInitialLines: 2,
      expectedChunks: [
        """
        @NonNull
        public static java.util.Optional<Item> find(@NonNull java.lang.String name, long limit, @NonNull Optional<String> tag, SwiftArena swiftArena) {
        """
      ]
    )
  }

  @Test
  func noAnnotationsByDefault() throws {
    try assertOutput(
      input: source,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public static java.util.Optional<Item> find(java.lang.String name, long limit, Optional<String> tag, SwiftArena swiftArena) {"
      ],
      notExpectedChunks: ["@NonNull", "@Nullable"]
    )
  }
}
