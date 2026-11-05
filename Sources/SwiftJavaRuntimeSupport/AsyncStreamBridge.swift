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

  @JavaMethod
  func fail(_ failure: Throwable?)
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
  nonisolated(unsafe) let stream = stream
  attachSource(to: javaStream, environment: environment, convert: convert) { deliver in
    for await element in stream {
      deliver(element)
    }
  }
}

/// Attaches a throwing stream like the `AsyncStream` overload; an error it throws is delivered to
/// the subscriber's `onError`.
public func _attachAsyncStream<Element, Failure: Error>(
  _ stream: AsyncThrowingStream<Element, Failure>,
  to javaStream: jobject?,
  environment: JNIEnvironment,
  convert: @escaping @Sendable (Element, JNIEnvironment) -> jobject?
) {
  nonisolated(unsafe) let stream = stream
  attachSource(to: javaStream, environment: environment, convert: convert) { deliver in
    for try await element in stream {
      deliver(element)
    }
  }
}

private func attachSource<Element>(
  to javaStream: jobject?,
  environment: JNIEnvironment,
  convert: @escaping @Sendable (Element, JNIEnvironment) -> jobject?,
  iterate: @escaping @Sendable (_ deliver: (Element) -> Void) async throws -> Void
) {
  guard let javaStream else { return }
  let source = SwiftAsyncStreamSource { delivery in
    nonisolated(unsafe) let delivery = delivery
    return Task {
      var failure: (any Error)?
      do {
        try await iterate { element in
          let environment = try! JavaVirtualMachine.shared().environment()
          // The frame frees the references made for the element: the value, and the delivery's wrapper.
          try! environment.withLocalFrame(capacity: 8) {
            let value = convert(element, environment)
            JavaSwiftAsyncStreamDelivery(javaThis: delivery, environment: environment)
              .next(value.map { JavaObject(javaThis: $0, environment: environment) })
          }
        }
      } catch {
        failure = error
      }
      let environment = try! JavaVirtualMachine.shared().environment()
      let javaDelivery = JavaSwiftAsyncStreamDelivery(javaThis: delivery, environment: environment)
      try! environment.withLocalFrame(capacity: 8) {
        if let failure, !Task.isCancelled, let throwable = environment.makeJavaThrowable(for: failure) {
          javaDelivery.fail(Throwable(javaThis: throwable, environment: environment))
        } else {
          javaDelivery.finish(!Task.isCancelled)
        }
      }
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
  return Int64(Int(bitPattern: Unmanaged.passRetained(SwiftTaskHandle(task)).toOpaque()))
}

@_cdecl("Java_org_swift_swiftkit_core_SwiftAsyncStream__00024cancelTask")
public func Java_org_swift_swiftkit_core_SwiftAsyncStream__00024cancelTask(
  environment: UnsafeMutablePointer<JNIEnv?>!,
  thisClass: jclass,
  task: jlong
) {
  Unmanaged<SwiftTaskHandle>.fromOpaque(UnsafeRawPointer(bitPattern: Int(task))!).takeUnretainedValue().task.cancel()
}

@_cdecl("Java_org_swift_swiftkit_core_SwiftAsyncStream__00024releaseTask")
public func Java_org_swift_swiftkit_core_SwiftAsyncStream__00024releaseTask(
  environment: UnsafeMutablePointer<JNIEnv?>!,
  thisClass: jclass,
  task: jlong
) {
  Unmanaged<SwiftTaskHandle>.fromOpaque(UnsafeRawPointer(bitPattern: Int(task))!).release()
}
