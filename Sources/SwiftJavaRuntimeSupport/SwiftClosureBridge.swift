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
import SwiftJavaJNICore

/// A Swift closure held by a Java `org.swift.swiftkit.core.SwiftClosure`.
final class SwiftClosureBox {
  let call: (_ arguments: jobjectArray?, _ environment: JNIEnvironment) -> jobject?

  init(_ call: @escaping (_ arguments: jobjectArray?, _ environment: JNIEnvironment) -> jobject?) {
    self.call = call
  }
}

/// The handle of a new Swift closure for a Java `SwiftClosure`, which takes ownership of it.
///
/// Used by generated code for functions returning closures: `call` converts the boxed Java
/// arguments, calls the closure and converts its result.
public func _makeSwiftClosure(
  _ call: @escaping (_ arguments: jobjectArray?, _ environment: JNIEnvironment) -> jobject?
) -> jlong {
  Int64(Int(bitPattern: Unmanaged.passRetained(SwiftClosureBox(call)).toOpaque()))
}

/// The argument at `index` of a `SwiftClosure` call.
public func _swiftClosureArgument(_ arguments: jobjectArray?, _ index: Int32, in environment: JNIEnvironment) -> jobject? {
  environment.interface.GetObjectArrayElement(environment, arguments, index)
}

@_cdecl("Java_org_swift_swiftkit_core_SwiftClosure__00024call")
public func Java_org_swift_swiftkit_core_SwiftClosure__00024call(
  environment: UnsafeMutablePointer<JNIEnv?>!,
  thisClass: jclass,
  handle: jlong,
  arguments: jobjectArray?
) -> jobject? {
  let box = Unmanaged<SwiftClosureBox>.fromOpaque(UnsafeRawPointer(bitPattern: Int(handle))!).takeUnretainedValue()
  return box.call(arguments, environment)
}

@_cdecl("Java_org_swift_swiftkit_core_SwiftClosure__00024release")
public func Java_org_swift_swiftkit_core_SwiftClosure__00024release(
  environment: UnsafeMutablePointer<JNIEnv?>!,
  thisClass: jclass,
  handle: jlong
) {
  Unmanaged<SwiftClosureBox>.fromOpaque(UnsafeRawPointer(bitPattern: Int(handle))!).release()
}

/// A Java object reference that a main-actor call hands back to the calling thread.
private struct _UncheckedJavaObject: @unchecked Sendable {
  let value: jobject?
}

/// Like `_makeSwiftClosure`, for a closure isolated to the main actor. Java has to call it on the
/// main thread, where Android and Compose run UI code; any other thread traps, as calling a
/// `@MainActor` function from Java does.
public func _makeMainActorSwiftClosure(
  _ call: @escaping @MainActor (_ arguments: jobjectArray?, _ environment: JNIEnvironment) -> jobject?
) -> jlong {
  _makeSwiftClosure { arguments, environment in
    nonisolated(unsafe) let arguments = arguments
    nonisolated(unsafe) let environment = environment
    return MainActor.assumeIsolated {
      _UncheckedJavaObject(value: call(arguments, environment))
    }.value
  }
}

private let completableFutureInit = _JNIMethodIDCache.Method(name: "<init>", signature: "()V")
private let completableFutureCache = _JNIMethodIDCache(
  className: "java/util/concurrent/CompletableFuture",
  methods: [completableFutureInit]
)

/// Runs an async closure called from Java in a new task, and returns a `CompletableFuture` that the
/// task completes with the closure's result, as a boxed Java value, or with its error as a `Throwable`.
public func _swiftClosureFuture(
  in environment: JNIEnvironment,
  _ body: @escaping @Sendable (_ environment: JNIEnvironment) async throws -> jobject?
) -> jobject? {
  let future = environment.interface.NewObjectA(
    environment,
    completableFutureCache.javaClass,
    completableFutureCache[completableFutureInit]!,
    nil
  )
  nonisolated(unsafe) let globalFuture = environment.interface.NewGlobalRef(environment, future)
  Task {
    let environment = try! JavaVirtualMachine.shared().environment()
    do {
      let result = try await body(environment)
      _ = environment.interface.CallBooleanMethodA(
        environment,
        globalFuture,
        _JNIMethodIDCache.CompletableFuture.complete,
        [jvalue(l: result)]
      )
    } catch {
      _ = environment.interface.CallBooleanMethodA(
        environment,
        globalFuture,
        _JNIMethodIDCache.CompletableFuture.completeExceptionally,
        [jvalue(l: environment.makeJavaThrowable(for: error))]
      )
    }
    environment.interface.DeleteGlobalRef(environment, globalFuture)
  }
  return future
}
