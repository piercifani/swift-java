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

@JavaClass("org.swift.swiftkit.core.SwiftAsyncStream")
class JavaSwiftAsyncStream: JavaObject {
  @JavaMethod
  func attachSource(_ handle: Int64)
}

@JavaClass("org.swift.swiftkit.core.SwiftAsyncStream$Delivery")
class JavaSwiftAsyncStreamDelivery: JavaObject {
  @JavaMethod
  func next(_ value: JavaObject?)

  @JavaMethod
  func finish(_ completed: Bool)
}

/// A Swift `AsyncStream` handed to Java, waiting for its single subscriber.
final class SwiftAsyncStreamSource: @unchecked Sendable {
  /// Starts iterating, delivering to the Java `Delivery` at the given global reference.
  let subscribe: @Sendable (_ delivery: jobject) -> Task<Void, Never>

  init(subscribe: @escaping @Sendable (_ delivery: jobject) -> Task<Void, Never>) {
    self.subscribe = subscribe
  }
}

/// Attaches `stream` to the Java `SwiftAsyncStream` the native call received. Each element is
/// converted with `convert` (to the Java value the generated `map` expects) when delivered.
///
/// Used by generated code for functions returning `AsyncStream`. A stream that is never
/// subscribed to is not released.
public func _attachAsyncStream<Element>(
  _ stream: AsyncStream<Element>,
  to javaStream: jobject?,
  environment: JNIEnvironment,
  convert: @escaping @Sendable (Element, JNIEnvironment) -> jobject?
) {
  guard let javaStream else { return }
  nonisolated(unsafe) let stream = stream
  let source = SwiftAsyncStreamSource { delivery in
    nonisolated(unsafe) let delivery = delivery
    return Task {
      for await element in stream {
        let environment = try! JavaVirtualMachine.shared().environment()
        let value = convert(element, environment)
        JavaSwiftAsyncStreamDelivery(javaThis: delivery, environment: environment)
          .next(value.map { JavaObject(javaThis: $0, environment: environment) })
        if let value {
          environment.interface.DeleteLocalRef(environment, value)
        }
      }
      let environment = try! JavaVirtualMachine.shared().environment()
      JavaSwiftAsyncStreamDelivery(javaThis: delivery, environment: environment).finish(!Task.isCancelled)
      environment.interface.DeleteGlobalRef(environment, delivery)
    }
  }
  let handle = Unmanaged.passRetained(source).toOpaque()
  JavaSwiftAsyncStream(javaThis: javaStream, environment: environment).attachSource(Int64(Int(bitPattern: handle)))
}

@_cdecl("Java_org_swift_swiftkit_core_SwiftAsyncStream__00024subscribe")
public func Java_org_swift_swiftkit_core_SwiftAsyncStream__00024subscribe(
  environment: UnsafeMutablePointer<JNIEnv?>!,
  thisClass: jclass,
  source: jlong,
  delivery: jobject?
) -> jlong {
  // The source is consumed: an AsyncStream has a single consumer.
  let source = Unmanaged<SwiftAsyncStreamSource>.fromOpaque(UnsafeRawPointer(bitPattern: Int(source))!).takeRetainedValue()
  let task = source.subscribe(environment.interface.NewGlobalRef(environment, delivery)!)
  return Int64(Int(bitPattern: Unmanaged.passRetained(AsyncStreamTaskHandle(task)).toOpaque()))
}

@_cdecl("Java_org_swift_swiftkit_core_SwiftAsyncStream__00024cancelTask")
public func Java_org_swift_swiftkit_core_SwiftAsyncStream__00024cancelTask(
  environment: UnsafeMutablePointer<JNIEnv?>!,
  thisClass: jclass,
  task: jlong
) {
  Unmanaged<AsyncStreamTaskHandle>.fromOpaque(UnsafeRawPointer(bitPattern: Int(task))!).takeUnretainedValue().task.cancel()
}

@_cdecl("Java_org_swift_swiftkit_core_SwiftAsyncStream__00024releaseTask")
public func Java_org_swift_swiftkit_core_SwiftAsyncStream__00024releaseTask(
  environment: UnsafeMutablePointer<JNIEnv?>!,
  thisClass: jclass,
  task: jlong
) {
  Unmanaged<AsyncStreamTaskHandle>.fromOpaque(UnsafeRawPointer(bitPattern: Int(task))!).release()
}

/// Keeps the task that delivers a stream's elements, behind the handle Java holds.
private final class AsyncStreamTaskHandle: @unchecked Sendable {
  let task: Task<Void, Never>

  init(_ task: Task<Void, Never>) {
    self.task = task
  }
}
