//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift.org project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift.org project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//


/// Where the Swift bindings come from that Swift calls Java implementations of protocols through, with
/// `enableJavaCallbacks`.
public enum JExtractJavaCallbacksBindings: String, Codable {
  /// The build plugin compiles the generated Java and runs wrap-java on it, which needs the SwiftPM
  /// sandbox disabled.
  case wrapJava

  /// jextract prints the bindings with the thunks, as it does for closures implemented in Java, so the
  /// build runs no Java tools.
  case jextract
}

extension JExtractJavaCallbacksBindings {
  public static var `default`: JExtractJavaCallbacksBindings {
    .wrapJava
  }
}
