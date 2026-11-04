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

import SwiftJava

extension JavaSwiftArena {
  /// A cache for the default auto arena found in SwiftKitCore.
  ///
  /// A constant (never reassigned), so generated code in Swift 6 language mode can read it.
  public nonisolated(unsafe) static let defaultAutoArena: JavaSwiftArena = {
    let swiftMemoryClass = try! JavaClass<SwiftJavaRuntimeSupport.JavaSwiftMemoryManagement>()
    return swiftMemoryClass.defaultSwiftJavaAutoArena
  }()
}
