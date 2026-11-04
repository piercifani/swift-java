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

public enum UploadError: Error {
  case rejected
}

/// Swift errors as values: Kotlin `Throwable`s.
public enum Uploads {
  /// A completion handler taking an optional error.
  public static func upload(_ id: String, onDone: @escaping (Error?) -> Void) {
    onDone(id.isEmpty ? UploadError.rejected : nil)
  }

  public static func failure(for id: String) -> Error? {
    id.isEmpty ? UploadError.rejected : nil
  }

  public static func isRejected(_ error: Error) -> Bool {
    (error as? UploadError) == .rejected
  }

  public static func describe(_ error: Error) -> String {
    "\(error)"
  }
}
