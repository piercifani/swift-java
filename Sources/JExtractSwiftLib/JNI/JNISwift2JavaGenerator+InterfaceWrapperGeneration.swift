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

import CodePrinting
import SwiftExtract
import SwiftJavaConfigurationShared
import SwiftJavaJNICore
import SwiftSyntax

extension JNISwift2JavaGenerator {

  func generateInterfaceWrappers(
    _ types: [ExtractedNominalType]
  ) -> [ExtractedNominalType: JavaInterfaceSwiftWrapper] {
    var wrappers = [ExtractedNominalType: JavaInterfaceSwiftWrapper]()

    for type in types where type.swiftNominal.kind == .protocol && type.swiftNominal.canBeImplementedInJava {
      // Skip protocols that have a known representative concrete type (e.g. DataProtocol).
      if let knownKind = type.swiftNominal.knownTypeKind,
        SwiftKnownTypes.representativeType(of: knownKind) != nil
      {
        continue
      }

      do {
        // wrap-java maps `java.net.URI` and the other Foundation Java types on its own terms, so
        // protocols implemented in Java don't pass Foundation values as they are; closures do.
        let nativeTranslation = NativeJavaTranslation(
          config: config,
          javaPackage: self.javaPackage,
          javaClassLookupTable: self.javaClassLookupTable,
          knownTypes: SwiftKnownTypes(symbolTable: lookupContext.symbolTable),
          protocolWrappers: [:],
          logger: self.logger
        )
        let translator = JavaInterfaceProtocolWrapperGenerator(
          asyncFuncMode: config.effectiveAsyncFuncMode,
          optionalsAsNullable: config.effectiveKotlinOutput,
          javaMapObjectBridge: nativeTranslation.javaMapObjectBridge,
          closureMethodName: usesWrapJavaBindings ? nil : config.effectiveClosureMethodName
        )
        wrappers[type] = try translator.generate(for: type)
      } catch {
        self.logger.warning("Failed to generate protocol wrapper for: '\(type.swiftNominal.qualifiedName)'; \(error)")
      }
    }

    return wrappers
  }

  /// A type that describes a Swift protocol
  /// that uses an underlying wrap-java `@JavaInterface`
  /// to make callbacks to Java from Swift using protocols.
  struct JavaInterfaceSwiftWrapper {
    let protocolType: SwiftNominalType
    let functions: [Function]
    let variables: [Variable]
    /// Requirements Swift can't call on a Java implementation yet.
    let unsupportedRequirements: [ExtractedFunc]
    let importedType: ExtractedNominalType

    var wrapperName: String {
      protocolType.nominalTypeDecl.javaInterfaceSwiftProtocolWrapperName
    }

    var swiftName: String {
      protocolType.nominalTypeDecl.qualifiedName
    }

    var javaInterfaceVariableName: String {
      protocolType.nominalTypeDecl.javaInterfaceVariableName
    }

    var javaInterfaceName: String {
      protocolType.nominalTypeDecl.javaInterfaceName
    }

    struct Function {
      let swiftFunctionName: String
      let originalFunctionSignature: SwiftFunctionSignature
      let swiftDecl: any DeclSyntaxProtocol
      let parameterConversions: [UpcallConversionStep]
      let resultConversion: UpcallConversionStep
    }

    struct Variable {
      let swiftDecl: any DeclSyntaxProtocol
      let getter: Function
      let setter: Function?
    }
  }

  /// Represents a synthetic protocol-like translation for escaping closures.
  struct SyntheticEscapingClosureFunctionType {
    /// The name of the Java functional interface to be generated.
    let javaInterfaceName: String

    /// Java binary name of the corresponding `@FunctionalInterface`.
    /// E.g. `com.example.swift.CallbackManager$setCallback$callback`.
    let javaBinaryName: String

    /// Conversion steps for each parameter
    let parameterConversions: [UpcallConversionStep]

    /// Conversion step for the result
    let resultConversion: UpcallConversionStep

    /// The name of the interface's single method, `apply` unless `closureMethodName` says otherwise
    let methodName: String

    /// The original Swift function type
    let functionType: SwiftFunctionType
  }

  struct JavaInterfaceProtocolWrapperGenerator {
    var asyncFuncMode: JExtractAsyncFuncMode = .default
    /// Foundation values are `JavaValue`s that cross as Java types, as `String` does. Only for closures, whose
    /// `@JavaInterface` jextract prints itself.
    var foundationTypesAsJavaTypes: Bool = false
    /// Protocols Java can implement (`enableJavaCallbacks`), by qualified name: a closure implemented in
    /// Java can return one of them, implemented in Java or in Swift.
    var javaImplementableProtocols: Set<String> = []
    /// Optional parameters cross as nullable Java objects (`kotlinOutput`), instead of Java optionals.
    var optionalsAsNullable: Bool = false
    /// With `dictionariesAsJavaMaps`, the bridge of a dictionary, `Any` or `AnyHashable` (or an optional of one),
    /// which crosses as the Java object the bridge makes.
    var javaMapObjectBridge: (SwiftType) throws -> String? = { _ in nil }
    /// A requirement's closure parameter crosses as its Java interface, which Java makes of a `SwiftClosure`
    /// with the factory its helper class declares. Needs jextract's bindings and the interface's own method name.
    var closureMethodName: String? = nil

    private func crossesAsIs(_ type: SwiftType) -> Bool {
      type.isDirectlyTranslatedToWrapJava || (foundationTypesAsJavaTypes && type.isFoundationJavaValue)
    }

    func generate(for type: ExtractedNominalType) throws -> JavaInterfaceSwiftWrapper {
      if !type.initializers.isEmpty
        || type.methods.contains(where: \.isStatic)
        || type.variables.contains(where: \.isStatic)
      {
        throw JavaTranslationError.protocolStaticRequirementsNotSupported
      }

      // A requirement Swift can't call on a Java implementation yet doesn't keep Java from implementing
      // the others: the wrapper stops with an error if it's called.
      var functions: [JavaInterfaceSwiftWrapper.Function] = []
      var unsupportedRequirements: [ExtractedFunc] = []
      for method in type.methods {
        do {
          functions.append(try translate(function: method))
        } catch {
          unsupportedRequirements.append(method)
        }
      }
      // FIXME: Finish support for variables
      unsupportedRequirements += type.variables

      return JavaInterfaceSwiftWrapper(
        protocolType: SwiftNominalType(nominalTypeDecl: type.swiftNominal),
        functions: functions,
        variables: [],
        unsupportedRequirements: unsupportedRequirements,
        importedType: type
      )
    }

    /// An `async` requirement implemented in Java returns a `CompletableFuture`, which the Swift
    /// wrapper awaits; its value arrives as a plain Java object. Supported results: `Void`, types
    /// translated directly (unboxed via `JavaBoxable`), and jextracted types.
    private func validateAsyncRequirement(_ signature: SwiftFunctionSignature) throws {
      try validateAsyncResult(signature.result.type)
    }

    /// An async requirement or closure implemented in Java returns a `CompletableFuture`: see `validateAsyncRequirement`.
    private func validateAsyncResult(_ resultType: SwiftType) throws {
      guard asyncFuncMode == .completableFuture else {
        // A `java.util.concurrent.Future` can't notify Swift when it completes.
        throw JavaTranslationError.asyncRequirementNeedsCompletableFuture
      }
      if resultType.isVoid {
        return
      }
      if case .nominal(let nominal) = resultType, let known = nominal.nominalTypeDecl.knownTypeKind {
        if known.isDirectlyTranslatedToWrapJava && known != .uint16 {
          return
        }
        throw JavaTranslationError.unsupportedSwiftType(resultType)
      }
      if case .nominal = resultType {
        return
      }
      throw JavaTranslationError.unsupportedSwiftType(resultType)
    }

    /// Generates a synthetic closure function translation.
    /// This treats the closure as if it were a protocol with a single `apply` method,
    /// allowing it to use the same conversion infrastructure for optionals, arrays, etc.
    func generateSyntheticClosureFunction(
      functionType: SwiftFunctionType,
      javaInterfaceName: String,
      javaBinaryName: String,
      methodName: String,
    ) throws -> SyntheticEscapingClosureFunctionType {
      if functionType.isAsync {
        try validateAsyncResult(functionType.resultType)
      }
      let parameterConversions = try functionType.parameters.enumerated().map { idx, param in
        let name = (param.parameterName ?? "_\(idx)").javaSafeIdentifier
        if case .function(let closure) = param.type {
          return try self.translateSwiftClosureArgument(name: name, closure: closure, interface: javaInterfaceName)
        }
        return try self.translateParameter(parameterName: name, type: param.type)
      }

      let resultConversion = try self.translateResult(
        type: functionType.resultType,
        methodName: methodName
      )

      return SyntheticEscapingClosureFunctionType(
        javaInterfaceName: javaInterfaceName,
        javaBinaryName: javaBinaryName,
        parameterConversions: parameterConversions,
        resultConversion: resultConversion,
        methodName: methodName,
        functionType: functionType
      )
    }

    /// A Swift closure passed to a closure implemented in Java, which keeps it to call later: a `SwiftClosure`
    /// Java wraps in the interface `interface` declares for it. Supported: escaping, synchronous closures
    /// returning nothing, taking strings, numbers and jextracted types, optional or not.
    private func translateSwiftClosureArgument(
      name: String,
      closure: SwiftFunctionType,
      interface: String
    ) throws -> UpcallConversionStep {
      guard closure.isEscaping, !closure.isAsync, closure.resultType.isVoid else {
        throw JavaTranslationError.unsupportedSwiftType(.function(closure))
      }
      func argumentConversion(_ type: SwiftType) throws -> String {
        if let bridge = try javaMapObjectBridge(type) {
          return "\(bridge).fromJavaObject(%ARG%, in: environment)"
        }
        guard case .nominal(let nominal) = type else {
          throw JavaTranslationError.unsupportedSwiftType(type)
        }
        if case .optional(let wrapped) = nominal.asKnownType {
          // `nil` when Java passes `null`: `SwiftClosure.call` passes a Java `Optional`'s value or `null`.
          return "(%ARG% == nil ? nil : \(try argumentConversion(wrapped)))"
        }
        switch nominal.nominalTypeDecl.knownTypeKind {
        case .string, .int64, .int32, .double, .bool:
          return "\(nominal.nominalTypeDecl.qualifiedName).fromJavaObject(%ARG%, in: environment)"
        case nil where !nominal.isSwiftJavaWrapper:
          return "UnsafeMutablePointer<\(nominal.nominalTypeDecl.qualifiedName)>(bitPattern: Int(JavaJNISwiftInstance(javaThis: %ARG%!, environment: environment)._memoryAddress()))!.pointee"
        default:
          throw JavaTranslationError.unsupportedSwiftType(type)
        }
      }
      let argumentConversions = try closure.parameters.map { try argumentConversion($0.type) }
      return .swiftClosureToJava(
        .placeholder,
        name: name,
        interfaceStruct: interface,
        argumentConversions: argumentConversions,
        isMainActor: closure.isMainActorIsolated
      )
    }

    private func translate(function: ExtractedFunc) throws -> JavaInterfaceSwiftWrapper.Function {
      if function.functionSignature.isAsync {
        try validateAsyncRequirement(function.functionSignature)
      }

      let parameters = try function.functionSignature.parameters.enumerated().map { idx, parameter in
        guard case .function(let closure) = parameter.type else {
          return try self.translateParameter(parameter)
        }
        guard let closureMethodName,
          KnownJavaFunctionalInterface.find(closure, closureMethodName: closureMethodName) == nil
        else {
          throw JavaTranslationError.unsupportedSwiftType(parameter.type)
        }
        // Named like the Java parameter; the interface struct is the requirement's, known once it's translated.
        let name = (parameter.parameterName ?? "arg\(idx)").javaSafeIdentifier.thunkSafeParameterName
        return try self.translateSwiftClosureArgument(name: name, closure: closure, interface: "")
      }

      let result = try translateResult(function.functionSignature.result, methodName: function.name)

      return JavaInterfaceSwiftWrapper.Function(
        swiftFunctionName: function.name,
        originalFunctionSignature: function.functionSignature,
        swiftDecl: function.swiftDecl,
        parameterConversions: parameters,
        resultConversion: result
      )
    }

    private func translateVariable(
      getter: ExtractedFunc,
      setter: ExtractedFunc?
    ) throws -> JavaInterfaceSwiftWrapper.Variable {
      try JavaInterfaceSwiftWrapper.Variable(
        swiftDecl: getter.swiftDecl, // they should be the same
        getter: translate(function: getter),
        setter: setter.map { try self.translate(function: $0) }
      )
    }

    private func translateParameter(_ parameter: SwiftParameter) throws -> UpcallConversionStep {
      try self.translateParameter(parameterName: parameter.parameterName!, type: parameter.type)
    }

    private func translateParameter(parameterName: String, type: SwiftType) throws -> UpcallConversionStep {

      if crossesAsIs(type) {
        return .placeholder
      }
      if let bridge = try javaMapObjectBridge(type) {
        return .bridgedToJava(.placeholder, bridge: bridge)
      }
      if type.isSwiftError {
        return .toJavaThrowable(.placeholder)
      }

      switch type {
      case .nominal(let nominalType):
        if let knownType = nominalType.asKnownType {
          switch knownType {
          case .optional(let wrapped):
            return try translateOptionalParameter(
              name: parameterName,
              wrappedType: wrapped
            )

          case .array(let element):
            return try translateArrayParameter(
              name: parameterName,
              elementType: element
            )

          default:
            throw JavaTranslationError.unsupportedSwiftType(type)
          }
        }

        // We assume this is then a JExtracted Swift class
        return .toJavaWrapper(
          .placeholder,
          name: parameterName,
          nominalType: nominalType
        )

      case .tuple([]): // void
        return .placeholder

      case .genericParameter, .function, .metatype, .tuple, .existential, .opaque, .composite, .inlineArray:
        throw JavaTranslationError.unsupportedSwiftType(type)
      }
    }

    private func translateArrayParameter(name: String, elementType: SwiftType) throws -> UpcallConversionStep {
      // An array of values that cross as they are (strings, numbers, Foundation values) is a `JavaValue` too.
      if crossesAsIs(elementType) {
        return .placeholder
      }
      switch elementType {
      case .nominal(let nominalType):
        if let knownType = nominalType.nominalTypeDecl.knownTypeKind {
          switch knownType {
          case .optional, .array, .dictionary, .set:
            throw JavaTranslationError.unsupportedSwiftType(known: .array(elementType))
          default:
            break
          }
        }

        // We assume this is a JExtracted type
        return .map(
          .placeholder,
          body: .toJavaWrapper(
            .placeholder,
            name: "arrayElement",
            nominalType: nominalType
          )
        )

      case .composite, .existential, .function, .genericParameter, .metatype, .opaque, .tuple, .inlineArray:
        throw JavaTranslationError.unsupportedSwiftType(known: .array(elementType))
      }
    }

    private func translateOptionalParameter(name: String, wrappedType: SwiftType) throws -> UpcallConversionStep {
      // `toJavaOptional()` needs a Java object; an array isn't one.
      if case .nominal(let nominal) = wrappedType, case .array = nominal.asKnownType {
        throw JavaTranslationError.unsupportedSwiftType(wrappedType)
      }
      if optionalsAsNullable {
        if let boxClass = wrappedType.javaBoxClassName {
          return .flatMap(.placeholder, body: .boxed(.placeholder, javaClass: boxClass))
        }
        return .flatMap(.placeholder, body: try translateParameter(parameterName: name, type: wrappedType))
      }
      let wrappedConversion = try translateParameter(parameterName: name, type: wrappedType)
      return .toJavaOptional(.map(.placeholder, body: wrappedConversion))
    }

    private func translateResult(_ result: SwiftResult, methodName: String) throws -> UpcallConversionStep {
      try self.translateResult(type: result.type, methodName: methodName)
    }

    private func translateResult(
      type: SwiftType,
      methodName: String,
      allowNilForObjects: Bool = false
    ) throws -> UpcallConversionStep {
      if crossesAsIs(type) {
        return .placeholder
      }
      if let bridge = try javaMapObjectBridge(type) {
        return .bridgedFromJava(.placeholder, bridge: bridge)
      }

      switch type {
      case .nominal(let nominalType):
        if let knownType = nominalType.asKnownType {
          switch knownType {
          case .optional(let wrapped):
            return try self.translateOptionalResult(
              wrappedType: wrapped,
              methodName: methodName
            )

          case .array(let element):
            return try self.translateArrayResult(elementType: element)

          default:
            throw JavaTranslationError.unsupportedSwiftType(type)
          }
        }

        let inner: UpcallConversionStep =
          !allowNilForObjects
          ? .unwrapOptional(.placeholder, message: "Upcall to \(methodName) unexpectedly returned nil")
          : .placeholder

        // We assume this is then a JExtracted Swift class
        return .toSwiftClass(
          inner,
          name: "result$",
          nominalType: nominalType
        )

      case .tuple([]): // void
        return .placeholder

      case .existential(let protocolType):
        guard let protocolDecl = protocolType.asNominalTypeDeclaration,
          javaImplementableProtocols.contains(protocolDecl.qualifiedName)
        else {
          throw JavaTranslationError.unsupportedSwiftType(type)
        }
        return .toSwiftExistential(
          .unwrapOptional(.placeholder, message: "Upcall to \(methodName) unexpectedly returned nil"),
          protocolDecl: protocolDecl
        )

      case .genericParameter, .function, .metatype, .tuple, .opaque, .composite, .inlineArray:
        throw JavaTranslationError.unsupportedSwiftType(type)
      }
    }

    private func translateArrayResult(elementType: SwiftType) throws -> UpcallConversionStep {
      switch elementType {
      case .nominal(let nominalType):
        if let knownType = nominalType.nominalTypeDecl.knownTypeKind {
          switch knownType {
          case .optional, .array, .dictionary, .set:
            throw JavaTranslationError.unsupportedSwiftType(known: .array(elementType))
          default:
            break
          }
        }

        // We assume this is a JExtracted type
        return .map(
          .placeholder,
          body: .toSwiftClass(
            .unwrapOptional(.placeholder, message: "Element of array was nil"),
            name: "arrayElement",
            nominalType: nominalType
          )
        )

      case .composite, .existential, .function, .genericParameter, .metatype, .opaque, .tuple, .inlineArray:
        throw JavaTranslationError.unsupportedSwiftType(known: .array(elementType))
      }
    }

    private func translateOptionalResult(wrappedType: SwiftType, methodName: String) throws -> UpcallConversionStep {
      // The Java `Optional` holds an array as an object: read it back as an array of the elements' Java objects.
      if case .nominal(let nominal) = wrappedType, case .array(let element) = nominal.asKnownType {
        guard case .nominal(let elementType) = element, elementType.nominalTypeDecl.knownTypeKind == nil,
          case .map(_, let elementConversion) = try translateArrayResult(elementType: element)
        else {
          throw JavaTranslationError.unsupportedSwiftType(wrappedType)
        }
        let javaArray = UpcallConversionStep.javaObjectArray(
          .placeholder,
          elementJavaClass: elementType.nominalTypeDecl.generatedJavaClassMacroName
        )
        return .map(.fromJavaOptional(.placeholder), body: .map(javaArray, body: elementConversion))
      }
      // The `fromJavaOptional` will handle the nullability
      let wrappedConversion = try translateResult(
        type: wrappedType,
        methodName: methodName,
        allowNilForObjects: true
      )
      return .map(.fromJavaOptional(.placeholder), body: wrappedConversion)
    }
  }
}

/// Describes how to convert values from and to wrap-java types
enum UpcallConversionStep {
  case placeholder

  case constant(String)

  indirect case toJavaWrapper(
    UpcallConversionStep,
    name: String,
    nominalType: SwiftNominalType
  )

  indirect case toSwiftClass(
    UpcallConversionStep,
    name: String,
    nominalType: SwiftNominalType
  )

  indirect case unwrapOptional(
    UpcallConversionStep,
    message: String
  )

  indirect case toJavaOptional(UpcallConversionStep)

  /// A Swift error as SwiftJava's `Throwable`.
  indirect case toJavaThrowable(UpcallConversionStep)

  /// A Swift value as the SwiftJava wrapper of the Java object `bridge` makes of it, `nil` for `null`.
  indirect case bridgedToJava(UpcallConversionStep, bridge: String)

  /// A SwiftJava wrapper as the Swift value `bridge` makes of its Java object.
  indirect case bridgedFromJava(UpcallConversionStep, bridge: String)

  indirect case fromJavaOptional(UpcallConversionStep)

  indirect case map(UpcallConversionStep, body: UpcallConversionStep)

  /// A Swift closure as the Java object the interface `interfaceStruct` makes of its `SwiftClosure`.
  /// `argumentConversions` turn each Java argument, `%ARG%`, into the closure's.
  indirect case swiftClosureToJava(
    UpcallConversionStep,
    name: String,
    interfaceStruct: String,
    argumentConversions: [String],
    isMainActor: Bool
  )

  indirect case flatMap(UpcallConversionStep, body: UpcallConversionStep)

  /// A string or number as its boxed Java object, such as `JavaLong`.
  indirect case boxed(UpcallConversionStep, javaClass: String)

  /// A Java array held as a plain Java object, as the Swift array of its elements' Java objects.
  indirect case javaObjectArray(UpcallConversionStep, elementJavaClass: String)

  /// A Java object implementing a Swift protocol, as the protocol's existential: the Swift value of a
  /// jextracted instance, or a Swift wrapper around a Java implementation.
  indirect case toSwiftExistential(UpcallConversionStep, protocolDecl: SwiftNominalTypeDeclaration)


  /// A Swift closure's conversion, made by the factory of the interface struct `interfaceStruct` names for it.
  func withClosureInterface(_ interfaceStruct: (_ name: String) -> String?) -> UpcallConversionStep {
    guard case .swiftClosureToJava(let inner, let name, _, let argumentConversions, let isMainActor) = self,
      let interfaceStruct = interfaceStruct(name)
    else {
      return self
    }
    return .swiftClosureToJava(
      inner,
      name: name,
      interfaceStruct: interfaceStruct,
      argumentConversions: argumentConversions,
      isMainActor: isMainActor
    )
  }

  /// Returns the conversion string applied to the placeholder.
  func render(_ printer: inout SwiftPrinter, _ placeholder: String) -> String {
    switch self {
    case .placeholder:
      return placeholder

    case .constant(let constant):
      return constant

    case .toJavaWrapper(let inner, let name, let nominalType):
      let inner = inner.render(&printer, placeholder)
      printer.print(
        """
        let \(name)Class = try! JavaClass<\(nominalType.nominalTypeDecl.generatedJavaClassMacroName)>(environment: JavaVirtualMachine.shared().environment())
        let \(name)Pointer = UnsafeMutablePointer<\(nominalType.nominalTypeDecl.qualifiedName)>.allocate(capacity: 1)
        \(name)Pointer.initialize(to: \(inner))
        """
      )

      return "\(name)Class.wrapMemoryAddressUnsafe(Int64(Int(bitPattern: \(name)Pointer)))"

    case .toSwiftClass(let inner, let name, let nominalType):
      let inner = inner.render(&printer, placeholder)

      // The wrap-java methods will return null
      printer.print(
        """
        let \(name)MemoryAddress$ = \(inner).as(JavaJNISwiftInstance.self)!.memoryAddress()
        let \(name)Pointer = UnsafeMutablePointer<\(nominalType.nominalTypeDecl.qualifiedName)>(bitPattern: Int(\(name)MemoryAddress$))!
        """
      )

      return "\(name)Pointer.pointee"

    case .unwrapOptional(let inner, let message):
      let inner = inner.render(&printer, placeholder)

      printer.print(
        """
        guard let unwrapped$ = \(inner) else {
          fatalError("\(message)")
        }
        """
      )

      return "unwrapped$"

    case .toJavaOptional(let inner):
      let inner = inner.render(&printer, placeholder)
      return "\(inner).toJavaOptional()"

    case .toJavaThrowable(let inner):
      let inner = inner.render(&printer, placeholder)
      return "_makeThrowable(for: \(inner))"

    case .bridgedToJava(let inner, let bridge):
      let inner = inner.render(&printer, placeholder)
      return "_javaObjectWrapper(\(inner), bridge: \(bridge).self)"

    case .bridgedFromJava(let inner, let bridge):
      let inner = inner.render(&printer, placeholder)
      return "_swiftValue(of: \(inner), bridge: \(bridge).self)"

    case .fromJavaOptional(let inner):
      let inner = inner.render(&printer, placeholder)
      return "Optional(javaOptional: \(inner))"

    case .toSwiftExistential(let inner, let protocolDecl):
      let inner = inner.render(&printer, placeholder)
      let existentialType = "any \(protocolDecl.qualifiedName)"
      printer.print(
        """
        let existential$: \(existentialType)
        if let instance$ = \(inner).as(JavaJNISwiftInstance.self) {
          let rawPointer$ = UnsafeMutableRawPointer(bitPattern: Int(instance$._memoryAddress()))!
          let dynamicType$ = unsafeBitCast(UnsafeRawPointer(bitPattern: Int(instance$._typeMetadataAddress()))!, to: Any.Type.self)
          func load$<T>(_ type: T.Type) -> \(existentialType) {
            rawPointer$.load(as: type) as! \(existentialType)
          }
          existential$ = _openExistential(dynamicType$, do: load$)
        } else {
          existential$ = \(protocolDecl.javaInterfaceSwiftImplementationName)(\(protocolDecl.javaInterfaceVariableName): \(protocolDecl.javaInterfaceName)(javaThis: \(inner).javaThis, environment: \(inner).javaEnvironment))
        }
        """
      )
      return "existential$"

    case .javaObjectArray(let inner, let elementJavaClass):
      let inner = inner.render(&printer, placeholder)
      return "[\(elementJavaClass)?](fromJNI: \(inner).javaThis, in: \(inner).javaEnvironment)"

    case .swiftClosureToJava(let inner, let name, let interfaceStruct, let argumentConversions, let isMainActor):
      let inner = inner.render(&printer, placeholder)
      let arguments = argumentConversions.enumerated().map { index, conversion in
        conversion.replacingOccurrences(of: "%ARG%", with: "_swiftClosureArgument(arguments$, \(index), in: environment)")
      }
      let makeClosure = isMainActor ? "_makeMainActorSwiftClosure" : "_makeSwiftClosure"
      printer.print(
        """
        let \(name)Closure$ = \(inner)
        let \(name)Handle$ = \(makeClosure) { arguments$, environment in
          \(name)Closure$(\(arguments.joined(separator: ", ")))
          return nil
        }
        """
      )
      return "try! JavaClass<\(interfaceStruct)>(environment: JavaVirtualMachine.shared().environment())._\(name)FromSwiftClosure(\(name)Handle$)"

    case .boxed(let inner, let javaClass):
      let inner = inner.render(&printer, placeholder)
      // The constructors of Java's boxed numbers are deprecated in favor of `valueOf`.
      if javaClass == "JavaString" {
        return "JavaString(\(inner))"
      }
      return "try! JavaClass<\(javaClass)>(environment: JavaVirtualMachine.shared().environment()).valueOf(\(inner))"

    case .flatMap(let inner, let body):
      let inner = inner.render(&printer, placeholder)
      var printer = SwiftPrinter()
      printer.printBraceBlock("\(inner).flatMap") { printer in
        let body = body.render(&printer, "$0")
        printer.print("return \(body)")
      }
      return printer.finalize()

    case .map(let inner, let body):
      let inner = inner.render(&printer, placeholder)
      var printer = SwiftPrinter()
      printer.printBraceBlock("\(inner).map") { printer in
        let body = body.render(&printer, "$0")
        printer.print("return \(body)")
      }
      return printer.finalize()
    }
  }
}

extension SwiftType {
  /// The SwiftJava class of the boxed Java object for a string or number, which a nullable one crosses as.
  var javaBoxClassName: String? {
    guard case .nominal(let nominal) = self else {
      return nil
    }
    switch nominal.nominalTypeDecl.knownTypeKind {
    case .string: return "JavaString"
    case .int64: return "JavaLong"
    case .int32: return "JavaInteger"
    case .double: return "JavaDouble"
    case .bool: return "JavaBoolean"
    default: return nil
    }
  }

  /// A Foundation value that conforms to `JavaValue` in SwiftJavaRuntimeSupport, used with `foundationTypesAsJavaTypes`
  var isFoundationJavaValue: Bool {
    guard case .nominal(let nominal) = self, let kind = nominal.nominalTypeDecl.knownTypeKind else {
      return false
    }
    switch kind {
    case .foundationURL, .essentialsURL, .foundationDate, .essentialsDate, .foundationData, .essentialsData,
      .foundationLocale, .essentialsLocale, .foundationTimeZone, .essentialsTimeZone:
      return true
    default:
      return false
    }
  }

  /// Indicates whether this type is translated by `wrap-java`
  /// into the same type as `jextract`.
  ///
  /// This means we do not have to perform any mapping when passing
  /// this type between jextract and wrap-java
  var isDirectlyTranslatedToWrapJava: Bool {
    switch self {
    case .nominal(let swiftNominalType):
      guard let knownType = swiftNominalType.asKnownType else {
        return false
      }
      switch knownType {
      case .bool, .int, .uint, .int8, .uint8, .int16, .uint16, .int32, .uint32, .int64, .uint64, .float, .double,
        .string, .void:
        return true
      case .array(let element):
        return element.isDirectlyTranslatedToWrapJava
      default:
        return false
      }

    case .genericParameter, .function, .metatype, .tuple, .existential, .opaque, .composite, .inlineArray:
      return false
    }
  }
}

extension SwiftNominalTypeDeclaration {
  /// Whether a Java class can implement this protocol: not if it refines a standard library protocol
  /// with requirements Java can't implement, such as `Encodable` or `Hashable`. Read from its declaration,
  /// so that modules depending on its module tell the same.
  var canBeImplementedInJava: Bool {
    let unimplementable: Set<String> = [
      "Encodable", "Decodable", "Codable", "Hashable", "Equatable", "Comparable", "Identifiable",
      "CustomStringConvertible", "CustomDebugStringConvertible", "Error", "LocalizedError", "RawRepresentable",
      "CaseIterable", "Sequence", "Collection", "AsyncSequence", "Actor",
    ]
    let inherited = syntax.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
    return !inherited.contains { unimplementable.contains($0) || unimplementable.contains($0.split(separator: ".").last.map(String.init) ?? "") }
  }
}
