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

// Bridges for `dictionariesAsJavaMaps`: a dictionary is copied to and from any `java.util.Map`, an
// optional is `null` for `nil`, and `Any` is converted by the type of its value.

/// A dictionary as a `java.util.LinkedHashMap` copy; any `java.util.Map` is copied back.
public enum MapBridge<KeyBridge: JobjectBridge, ValueBridge: JobjectBridge>: JobjectBridge
where KeyBridge.SwiftType: Hashable {
  public typealias SwiftType = [KeyBridge.SwiftType: ValueBridge.SwiftType]

  public static func toJavaObject(_ value: SwiftType, in environment: JNIEnvironment) -> jobject? {
    _JavaCollections.newMap(value, in: environment) { key, value in
      (KeyBridge.toJavaObject(key, in: environment), ValueBridge.toJavaObject(value, in: environment))
    }
  }

  public static func fromJavaObject(_ obj: jobject?, in environment: JNIEnvironment) -> SwiftType {
    guard let obj else {
      fatalError("Map.fromJavaObject received a null Java object")
    }
    var result: SwiftType = [:]
    _JavaCollections.forEachEntry(of: obj, in: environment) { key, value in
      result[KeyBridge.fromJavaObject(key, in: environment)] = ValueBridge.fromJavaObject(value, in: environment)
    }
    return result
  }

  public static func withJNIClass<Result>(
    in environment: JNIEnvironment,
    _ body: (jclass) throws -> Result
  ) throws -> Result {
    try body(_JavaCollections.map.javaClass)
  }
}

/// An optional as its wrapped value's Java object, `null` for `nil`.
public enum NullableBridge<WrappedBridge: JobjectBridge>: JobjectBridge {
  public typealias SwiftType = WrappedBridge.SwiftType?

  public static func toJavaObject(_ value: SwiftType, in environment: JNIEnvironment) -> jobject? {
    value.flatMap { WrappedBridge.toJavaObject($0, in: environment) }
  }

  public static func fromJavaObject(_ obj: jobject?, in environment: JNIEnvironment) -> SwiftType {
    obj.map { WrappedBridge.fromJavaObject($0, in: environment) }
  }

  public static func withJNIClass<Result>(
    in environment: JNIEnvironment,
    _ body: (jclass) throws -> Result
  ) throws -> Result {
    try WrappedBridge.withJNIClass(in: environment, body)
  }
}

/// `Any` as a `java.lang.Object`, by the type of its value: a boxed string, number or boolean, a
/// `java.util.List` for an array, a `java.util.Map` for a dictionary and a `java.util.Set` for a set.
/// Java objects come back as the same Swift types, a `Long` as an `Int`.
public enum AnyBridge: JobjectBridge {
  public typealias SwiftType = Any

  public static func toJavaObject(_ value: Any, in environment: JNIEnvironment) -> jobject? {
    _JavaCollections.javaObject(of: value, in: environment)
  }

  public static func fromJavaObject(_ obj: jobject?, in environment: JNIEnvironment) -> Any {
    guard let value = _JavaCollections.swiftValue(of: obj, in: environment) else {
      fatalError("Any.fromJavaObject received a null Java object")
    }
    return value
  }

  public static func withJNIClass<Result>(
    in environment: JNIEnvironment,
    _ body: (jclass) throws -> Result
  ) throws -> Result {
    try body(_JavaCollections.object.javaClass)
  }
}

/// `AnyHashable` as `AnyBridge` converts its base.
public enum AnyHashableBridge: JobjectBridge {
  public typealias SwiftType = AnyHashable

  public static func toJavaObject(_ value: AnyHashable, in environment: JNIEnvironment) -> jobject? {
    _JavaCollections.javaObject(of: value.base, in: environment)
  }

  public static func fromJavaObject(_ obj: jobject?, in environment: JNIEnvironment) -> AnyHashable {
    guard let value = _JavaCollections.swiftValue(of: obj, in: environment) as? AnyHashable else {
      fatalError("AnyHashable.fromJavaObject received a null or unhashable Java object")
    }
    return value
  }

  public static func withJNIClass<Result>(
    in environment: JNIEnvironment,
    _ body: (jclass) throws -> Result
  ) throws -> Result {
    try body(_JavaCollections.object.javaClass)
  }
}

/// A Swift value converted by `bridge`, as the SwiftJava wrapper a Java method binding takes; `nil` for `null`.
public func _javaObjectWrapper<Bridge: JobjectBridge, Wrapper: AnyJavaObject>(
  _ value: Bridge.SwiftType,
  bridge: Bridge.Type
) -> Wrapper? {
  let environment = try! JavaVirtualMachine.shared().environment()
  return Bridge.toJavaObject(value, in: environment).map { Wrapper(javaThis: $0, environment: environment) }
}

/// The Java object a Java method returned, as the Swift value `bridge` converts it to.
public func _swiftValue<Bridge: JobjectBridge>(of wrapper: (some AnyJavaObject)?, bridge: Bridge.Type) -> Bridge.SwiftType {
  let environment = try! JavaVirtualMachine.shared().environment()
  return Bridge.fromJavaObject(wrapper?.javaThis, in: environment)
}

enum _JavaCollections {
  private static let mapEntrySet = _JNIMethodIDCache.Method(name: "entrySet", signature: "()Ljava/util/Set;")
  static let map = _JNIMethodIDCache(className: "java/util/Map", methods: [mapEntrySet])

  private static let linkedHashMapInit = _JNIMethodIDCache.Method(name: "<init>", signature: "(I)V")
  private static let linkedHashMapPut = _JNIMethodIDCache.Method(
    name: "put",
    signature: "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"
  )
  private static let linkedHashMap = _JNIMethodIDCache(
    className: "java/util/LinkedHashMap",
    methods: [linkedHashMapInit, linkedHashMapPut]
  )

  private static let entryKey = _JNIMethodIDCache.Method(name: "getKey", signature: "()Ljava/lang/Object;")
  private static let entryValue = _JNIMethodIDCache.Method(name: "getValue", signature: "()Ljava/lang/Object;")
  private static let entry = _JNIMethodIDCache(className: "java/util/Map$Entry", methods: [entryKey, entryValue])

  private static let collectionIterator = _JNIMethodIDCache.Method(
    name: "iterator",
    signature: "()Ljava/util/Iterator;"
  )
  private static let collectionAdd = _JNIMethodIDCache.Method(name: "add", signature: "(Ljava/lang/Object;)Z")
  private static let collection = _JNIMethodIDCache(
    className: "java/util/Collection",
    methods: [collectionIterator, collectionAdd]
  )

  private static let iteratorHasNext = _JNIMethodIDCache.Method(name: "hasNext", signature: "()Z")
  private static let iteratorNext = _JNIMethodIDCache.Method(name: "next", signature: "()Ljava/lang/Object;")
  private static let iterator = _JNIMethodIDCache(
    className: "java/util/Iterator",
    methods: [iteratorHasNext, iteratorNext]
  )

  private static let sizedInit = _JNIMethodIDCache.Method(name: "<init>", signature: "(I)V")
  private static let arrayList = _JNIMethodIDCache(className: "java/util/ArrayList", methods: [sizedInit])
  private static let linkedHashSet = _JNIMethodIDCache(className: "java/util/LinkedHashSet", methods: [sizedInit])
  private static let list = _JNIMethodIDCache(className: "java/util/List")
  private static let set = _JNIMethodIDCache(className: "java/util/Set")
  static let object = _JNIMethodIDCache(className: "java/lang/Object")

  static func newMap<Key, Value>(
    _ dictionary: [Key: Value],
    in environment: JNIEnvironment,
    _ convert: (Key, Value) -> (jobject?, jobject?)
  ) -> jobject? {
    var sizeArgs = [jvalue()]
    sizeArgs[0].i = jint(dictionary.count)
    let map = environment.interface.NewObjectA(
      environment,
      linkedHashMap.javaClass,
      linkedHashMap.methods[linkedHashMapInit]!,
      &sizeArgs
    )
    for (key, value) in dictionary {
      let (javaKey, javaValue) = convert(key, value)
      var args = [jvalue(), jvalue()]
      args[0].l = javaKey
      args[1].l = javaValue
      let previous = environment.interface.CallObjectMethodA(
        environment,
        map,
        linkedHashMap.methods[linkedHashMapPut]!,
        &args
      )
      deleteLocalRefs([previous, javaKey, javaValue], in: environment)
    }
    return map
  }

  static func forEachEntry(of map: jobject, in environment: JNIEnvironment, _ body: (jobject?, jobject?) -> Void) {
    let entries = environment.interface.CallObjectMethodA(environment, map, Self.map.methods[mapEntrySet]!, nil)
    forEachElement(of: entries, in: environment) { entry in
      let key = environment.interface.CallObjectMethodA(environment, entry, Self.entry.methods[entryKey]!, nil)
      let value = environment.interface.CallObjectMethodA(environment, entry, Self.entry.methods[entryValue]!, nil)
      body(key, value)
      deleteLocalRefs([key, value], in: environment)
    }
    deleteLocalRefs([entries], in: environment)
  }

  static func forEachElement(of collection: jobject?, in environment: JNIEnvironment, _ body: (jobject?) -> Void) {
    let iterator = environment.interface.CallObjectMethodA(
      environment,
      collection,
      Self.collection.methods[collectionIterator]!,
      nil
    )
    let hasNext = Self.iterator.methods[iteratorHasNext]!
    let next = Self.iterator.methods[iteratorNext]!
    while environment.interface.CallBooleanMethodA(environment, iterator, hasNext, nil) == JNI_TRUE {
      let element = environment.interface.CallObjectMethodA(environment, iterator, next, nil)
      body(element)
      deleteLocalRefs([element], in: environment)
    }
    deleteLocalRefs([iterator], in: environment)
  }

  private static func newCollection(
    _ cache: _JNIMethodIDCache,
    _ elements: some Collection<Any>,
    in environment: JNIEnvironment
  ) -> jobject? {
    var sizeArgs = [jvalue()]
    sizeArgs[0].i = jint(elements.count)
    let collection = environment.interface.NewObjectA(environment, cache.javaClass, cache.methods[sizedInit]!, &sizeArgs)
    for element in elements {
      var args = [jvalue()]
      args[0].l = javaObject(of: element, in: environment)
      _ = environment.interface.CallBooleanMethodA(environment, collection, Self.collection.methods[collectionAdd]!, &args)
      deleteLocalRefs([args[0].l], in: environment)
    }
    return collection
  }

  /// The Java object for a Swift value of any type, as Skip bridges `Any`; `null` for `nil`.
  static func javaObject(of value: Any, in environment: JNIEnvironment) -> jobject? {
    if let optional = value as? _OptionalValue {
      guard let wrapped = optional._wrapped else {
        return nil
      }
      return javaObject(of: wrapped, in: environment)
    }
    if let hashable = value as? AnyHashable, type(of: value) == AnyHashable.self {
      return javaObject(of: hashable.base, in: environment)
    }
    switch value {
    case let boxable as any JavaBoxable:
      return boxable.toJavaObject(in: environment)
    case let javaValue as any _JNIObjectJavaValue:
      return javaValue.getJNIValue(in: environment)
    case let dictionary as [AnyHashable: Any]:
      return newMap(dictionary, in: environment) { key, value in
        (javaObject(of: key.base, in: environment), javaObject(of: value, in: environment))
      }
    case let set as Set<AnyHashable>:
      return newCollection(linkedHashSet, set.lazy.map { $0.base }, in: environment)
    case let array as [Any]:
      return newCollection(arrayList, array, in: environment)
    default:
      fatalError("Unable to convert Swift value \(value) of type \(type(of: value)) to a Java object")
    }
  }

  /// The Swift value for a Java object, as Skip bridges `Any`; `nil` for `null`.
  static func swiftValue(of obj: jobject?, in environment: JNIEnvironment) -> Any? {
    guard let obj else {
      return nil
    }
    func isInstance(_ javaClass: jclass) -> Bool {
      environment.interface.IsInstanceOf(environment, obj, javaClass) == JNI_TRUE
    }
    if isInstance(String.javaBoxClass) { return String.fromJavaObject(obj, in: environment) }
    if isInstance(Bool.javaBoxClass) { return Bool.fromJavaObject(obj, in: environment) }
    if isInstance(Int.javaBoxClass) { return Int.fromJavaObject(obj, in: environment) }
    if isInstance(Int32.javaBoxClass) { return Int32.fromJavaObject(obj, in: environment) }
    if isInstance(Double.javaBoxClass) { return Double.fromJavaObject(obj, in: environment) }
    if isInstance(Float.javaBoxClass) { return Float.fromJavaObject(obj, in: environment) }
    if isInstance(Int16.javaBoxClass) { return Int16.fromJavaObject(obj, in: environment) }
    if isInstance(Int8.javaBoxClass) { return Int8.fromJavaObject(obj, in: environment) }
    if isInstance(map.javaClass) {
      var dictionary: [AnyHashable: Any] = [:]
      forEachEntry(of: obj, in: environment) { key, value in
        guard let key = swiftValue(of: key, in: environment) as? AnyHashable else {
          fatalError("A Java map's key isn't hashable in Swift")
        }
        dictionary[key] = swiftValue(of: value, in: environment)
      }
      return dictionary
    }
    if isInstance(list.javaClass) {
      var array: [Any] = []
      forEachElement(of: obj, in: environment) { element in
        array.append(swiftValue(of: element, in: environment) as Any)
      }
      return array
    }
    if isInstance(set.javaClass) {
      var result: Set<AnyHashable> = []
      forEachElement(of: obj, in: environment) { element in
        if let element = swiftValue(of: element, in: environment) as? AnyHashable {
          result.insert(element)
        }
      }
      return result
    }
    fatalError("Unable to convert a Java object to a Swift value")
  }

  private static func deleteLocalRefs(_ refs: [jobject?], in environment: JNIEnvironment) {
    for case let ref? in refs {
      environment.interface.DeleteLocalRef(environment, ref)
    }
  }
}

/// Unwraps an optional held in an `Any`.
private protocol _OptionalValue {
  var _wrapped: Any? { get }
}

extension Optional: _OptionalValue {
  fileprivate var _wrapped: Any? {
    self.map { $0 as Any }
  }
}
