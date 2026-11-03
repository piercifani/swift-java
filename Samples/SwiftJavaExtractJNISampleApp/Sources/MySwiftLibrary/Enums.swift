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

public enum EnumWithValueCases {
  case firstCase(UInt)
  case secondCase
}

public enum EnumWithBacktick {
  case `let`
  case `default`
}

public enum EnumWithCaseNameValue {
  case success(Success)
  public struct Success {
    public init(message: String) {
      self.message = message
    }
    public var message: String
  }
}

public enum ComplexAssociatedValues {
  case generic(MyID<Int>, GenericEnum<Int>)
  case optionalTypealiasedGeneric(id: MyIntID?)
  case array([String])
}

/// A case named like its payload type: the Java record `Case.MySwiftStruct` would shadow
/// the `MySwiftStruct` class without qualification.
public enum StructHolder {
  case empty
  case mySwiftStruct(MySwiftStruct)

  public static func holding(len: Int64) -> StructHolder {
    .mySwiftStruct(MySwiftStruct(cap: len, len: len))
  }
}
