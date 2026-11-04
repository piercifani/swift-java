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

public enum SampleError: Error {
  case offline
  case timeout
}

/// Not jextracted: crosses as a `SwiftErrorException` holding the Swift value.
struct CodedError: Error {
  let code: Int64
}

/// Swift errors as values: Java `Throwable`s.
public enum ErrorValues {
  public static func make(offline: Bool) -> Error? {
    offline ? SampleError.offline : nil
  }

  public static func isOffline(_ error: Error) -> Bool {
    (error as? SampleError) == .offline
  }

  public static func coded(_ code: Int64) -> any Error {
    CodedError(code: code)
  }

  public static func code(_ error: any Error) -> Int64 {
    (error as? CodedError)?.code ?? -1
  }

  public static func describe(_ error: Error) -> String {
    "\(error)"
  }

  public static func roundTrip(_ error: Error?) -> Error? {
    error
  }

  public static func report(_ callback: @escaping (Error?) -> Void) {
    callback(SampleError.timeout)
    callback(nil)
  }

  public static func makeLogger() -> (Error) -> String {
    { "logged: \($0)" }
  }
}
