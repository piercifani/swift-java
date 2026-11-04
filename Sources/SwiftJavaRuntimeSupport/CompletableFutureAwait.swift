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

@JavaClass("java.util.concurrent.CompletableFuture")
public class JavaCompletableFuture: JavaObject {
  @JavaMethod
  func cancel(_ mayInterruptIfRunning: Bool) -> Bool
}

@JavaClass("org.swift.swiftkit.core.CompletableFutureContinuation")
class JavaCompletableFutureContinuation: JavaObject {}

extension JavaClass<JavaCompletableFutureContinuation> {
  @JavaStaticMethod
  func resumeWhenComplete(_ future: JavaCompletableFuture?, _ continuation: Int64)
}

/// The completion of a `CompletableFuture`, as global references so it can cross threads.
private struct CompletableFutureOutcome: @unchecked Sendable {
  let value: jobject?
  let error: jobject?
}

private final class CompletableFutureContinuationBox: @unchecked Sendable {
  let continuation: CheckedContinuation<CompletableFutureOutcome, Never>

  init(_ continuation: CheckedContinuation<CompletableFutureOutcome, Never>) {
    self.continuation = continuation
  }
}

/// Awaits a Java `CompletableFuture` without blocking a thread: Java resumes this task when the
/// future completes. Cancelling the task cancels the future. Returns the future's value (nil for
/// `null`), or throws the exception it completed with.
///
/// Used by generated code for `async` protocol requirements implemented in Java.
public func _awaitCompletableFuture(_ future: JavaCompletableFuture) async throws -> JavaObject? {
  let environment = try JavaVirtualMachine.shared().environment()
  // A global reference, usable from whichever thread completes, cancels or resumes.
  nonisolated(unsafe) let futureRef = environment.interface.NewGlobalRef(environment, future.javaThis)!
  defer {
    let environment = try! JavaVirtualMachine.shared().environment()
    environment.interface.DeleteGlobalRef(environment, futureRef)
  }

  let outcome = await withTaskCancellationHandler {
    await withCheckedContinuation { (continuation: CheckedContinuation<CompletableFutureOutcome, Never>) in
      let box = Unmanaged.passRetained(CompletableFutureContinuationBox(continuation)).toOpaque()
      let environment = try! JavaVirtualMachine.shared().environment()
      let continuationClass = try! JavaClass<JavaCompletableFutureContinuation>(environment: environment)
      continuationClass.resumeWhenComplete(
        JavaCompletableFuture(javaThis: futureRef, environment: environment),
        Int64(Int(bitPattern: box))
      )
    }
  } onCancel: {
    let environment = try! JavaVirtualMachine.shared().environment()
    _ = JavaCompletableFuture(javaThis: futureRef, environment: environment).cancel(true)
  }

  // Wrap the results with this thread's environment, then drop the cross-thread references.
  let resumedEnvironment = try JavaVirtualMachine.shared().environment()
  defer {
    if let value = outcome.value { resumedEnvironment.interface.DeleteGlobalRef(resumedEnvironment, value) }
    if let error = outcome.error { resumedEnvironment.interface.DeleteGlobalRef(resumedEnvironment, error) }
  }
  if let error = outcome.error {
    throw Throwable(javaThis: error, environment: resumedEnvironment)
  }
  return outcome.value.map { JavaObject(javaThis: $0, environment: resumedEnvironment) }
}

@_cdecl("Java_org_swift_swiftkit_core_CompletableFutureContinuation__00024resume")
public func Java_org_swift_swiftkit_core_CompletableFutureContinuation__00024resume(
  environment: UnsafeMutablePointer<JNIEnv?>!,
  thisClass: jclass,
  continuation: jlong,
  value: jobject?,
  error: jthrowable?
) {
  let box = Unmanaged<CompletableFutureContinuationBox>
    .fromOpaque(UnsafeRawPointer(bitPattern: Int(continuation))!)
    .takeRetainedValue()
  box.continuation.resume(
    returning: CompletableFutureOutcome(
      value: value.flatMap { environment.interface.NewGlobalRef(environment, $0) },
      error: error.flatMap { environment.interface.NewGlobalRef(environment, $0) }
    )
  )
}

// ==== -----------------------------------------------------------------------
// MARK: Cancelling the Swift task behind an exported `async` function

@JavaClass("org.swift.swiftkit.core.CompletableFutureCancellation")
class JavaCompletableFutureCancellation: JavaObject {}

extension JavaClass<JavaCompletableFutureCancellation> {
  @JavaStaticMethod
  func cancelTaskWhenCancelled(_ future: JavaCompletableFuture?, _ task: Int64)
}

private final class SwiftTaskHandle: @unchecked Sendable {
  let task: Task<Void, Never>

  init(_ task: Task<Void, Never>) {
    self.task = task
  }
}

/// Cancels `task` when the Java `future` it completes is cancelled.
///
/// Used by generated code for `async` functions exported to Java. Pass the future the native call
/// received, which stays valid for the duration of the call even if the task has already finished.
public func _cancelTaskWhenFutureIsCancelled(
  _ future: jobject?,
  task: Task<Void, Never>,
  environment: JNIEnvironment
) {
  guard let future else { return }
  let handle = Unmanaged.passRetained(SwiftTaskHandle(task)).toOpaque()
  let cancellationClass = try! JavaClass<JavaCompletableFutureCancellation>(environment: environment)
  cancellationClass.cancelTaskWhenCancelled(
    JavaCompletableFuture(javaThis: future, environment: environment),
    Int64(Int(bitPattern: handle))
  )
}

@_cdecl("Java_org_swift_swiftkit_core_CompletableFutureCancellation__00024cancelTask")
public func Java_org_swift_swiftkit_core_CompletableFutureCancellation__00024cancelTask(
  environment: UnsafeMutablePointer<JNIEnv?>!,
  thisClass: jclass,
  task: jlong
) {
  Unmanaged<SwiftTaskHandle>.fromOpaque(UnsafeRawPointer(bitPattern: Int(task))!).takeUnretainedValue().task.cancel()
}

@_cdecl("Java_org_swift_swiftkit_core_CompletableFutureCancellation__00024releaseTask")
public func Java_org_swift_swiftkit_core_CompletableFutureCancellation__00024releaseTask(
  environment: UnsafeMutablePointer<JNIEnv?>!,
  thisClass: jclass,
  task: jlong
) {
  Unmanaged<SwiftTaskHandle>.fromOpaque(UnsafeRawPointer(bitPattern: Int(task))!).release()
}
