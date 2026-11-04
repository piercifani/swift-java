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
  var javaTranslator: JavaTranslation {
    JavaTranslation(
      config: config,
      swiftModuleName: swiftModuleName,
      javaPackage: self.javaPackage,
      javaClassLookupTable: self.javaClassLookupTable,
      moduleJavaPackages: self.moduleJavaPackages,
      knownTypes: SwiftKnownTypes(symbolTable: lookupContext.symbolTable),
      protocolWrappers: self.interfaceProtocolWrappers,
      logger: self.logger,
      javaCallbackModules: self.javaCallbackModules,
      errorTypes: self.swiftErrorTypes,
      javaIdentifiers: self.currentJavaIdentifiers
    )
  }

  func translatedDecl(
    for decl: ExtractedFunc
  ) -> TranslatedFunctionDecl? {
    if let cached = translatedDecls[decl] {
      return cached
    }

    var translated: TranslatedFunctionDecl?
    do {
      var translator = self.javaTranslator
      translator.closureInterfaceOwner = self.closureInterfaceOwner(for: decl)
      translated = try translator.translate(decl)
    } catch {
      reportSkipped(decl.swiftDecl.qualifiedNameForDebug, reason: "\(error)")
      translated = nil
    }

    if let candidate = translated, collidesWithThrowableMember(candidate, of: decl) {
      skippedDeclarations.append("\(decl.swiftDecl.qualifiedNameForDebug): collides with a java.lang.Throwable member")
      translated = nil
    }

    if var candidate = translated {
      candidate.nativeFunctionName = uniqueNativeFunctionName(candidate)
      translated = candidate
    }

    // `updateValue` so a failure (nil) is cached too; subscript-assigning nil would remove the key.
    translatedDecls.updateValue(translated, forKey: decl)
    return translated
  }

  /// Logs a declaration that analysis accepted but JNI translation could not handle, and records it
  /// for `failOnSkippedDeclarations`. These used to be logged at debug level only.
  private func reportSkipped(_ name: String, reason: String) {
    self.logger.warning("Failed to translate: '\(name)' in module '\(swiftModuleName)'; \(reason)")
    skippedDeclarations.append("\(name): \(reason)")
  }

  /// Overloads with different Java parameter types can still lower to the same native signature, since
  /// every jextracted type is passed as a `long`: `init(standard: StandardMarket)` and
  /// `init(sports: SportsMarket)` both need `$init(long)`. Later ones get a `$1`, `$2`… suffix.
  private func uniqueNativeFunctionName(_ translated: TranslatedFunctionDecl) -> String {
    let parameterTypes = translated.nativeParameters.map { "\($0.type)" }.joined(separator: ",")
    let key = "\(translated.parentName).\(translated.nativeFunctionName)(\(parameterTypes))"
    let count = nativeFunctionNames[key, default: 0]
    nativeFunctionNames[key] = count + 1
    return count == 0 ? translated.nativeFunctionName : "\(translated.nativeFunctionName)$\(count)"
  }

  /// Zero-argument `Throwable` members that a generated `SwiftError` subclass cannot redeclare with another meaning.
  static let throwableMemberNames: Set<String> = [
    "getMessage", "getLocalizedMessage", "getCause", "fillInStackTrace", "printStackTrace", "getStackTrace",
    "getSuppressed",
  ]

  /// Whether `translated`, a member of an error type, would clash with a `java.lang.Throwable` method
  /// on the generated exception class, in which case it is skipped with a warning.
  private func collidesWithThrowableMember(_ translated: TranslatedFunctionDecl, of decl: ExtractedFunc) -> Bool {
    guard let parent = decl.parentType?.asNominalTypeDeclaration,
      self.swiftErrorTypes.contains(parent.identity),
      translated.translatedFunctionSignature.parameters.isEmpty,
      Self.throwableMemberNames.contains(translated.name)
    else {
      return false
    }

    // `getMessage()`/`getLocalizedMessage()` returning a String naturally override the Throwable ones.
    let isStringOverride =
      ["getMessage", "getLocalizedMessage"].contains(translated.name)
      && translated.translatedFunctionSignature.result.javaType == .javaLangString
    if isStringOverride {
      return false
    }

    self.logger.warning(
      "Skipping '\(parent.qualifiedName).\(translated.name)': it collides with 'java.lang.Throwable.\(translated.name)()' on the generated exception class."
    )
    return true
  }

  func translatedEnumCase(
    for decl: ExtractedEnumCase
  ) -> TranslatedEnumCase? {
    if let cached = translatedEnumCases[decl] {
      return cached
    }

    let translated: TranslatedEnumCase?
    do {
      let translation = JavaTranslation(
        config: config,
        swiftModuleName: swiftModuleName,
        javaPackage: self.javaPackage,
        javaClassLookupTable: self.javaClassLookupTable,
        moduleJavaPackages: self.moduleJavaPackages,
        knownTypes: SwiftKnownTypes(symbolTable: lookupContext.symbolTable),
        protocolWrappers: self.interfaceProtocolWrappers,
        logger: self.logger,
        javaCallbackModules: self.javaCallbackModules,
        errorTypes: self.swiftErrorTypes,
        javaIdentifiers: self.currentJavaIdentifiers,
      )
      translated = try translation.translate(enumCase: decl)
    } catch {
      reportSkipped(decl.swiftDecl.qualifiedNameForDebug, reason: "\(error)")
      translated = nil
    }

    translatedEnumCases.updateValue(translated, forKey: decl)
    return translated
  }

  struct JavaTranslation {
    let config: Configuration
    let swiftModuleName: String
    let javaPackage: String
    let javaClassLookupTable: JavaClassLookupTable
    let moduleJavaPackages: ModuleJavaPackages
    var knownTypes: SwiftKnownTypes
    let protocolWrappers: [ExtractedNominalType: JavaInterfaceSwiftWrapper]
    let logger: Logger
    var javaCallbackModules: Set<String> = []
    /// Module-qualified identities of extracted types that are surfaced to Java as `SwiftError` exceptions.
    let errorTypes: Set<SwiftNominalIdentity>
    var javaIdentifiers: JavaIdentifierFactory
    /// For a method implementing a protocol requirement, the protocol: closure parameters use its
    /// functional interfaces, so that the Java method overrides the interface's.
    var closureInterfaceOwner: ClosureInterfaceOwner? = nil

    func translate(enumCase: ExtractedEnumCase) throws -> TranslatedEnumCase {
      let methodName = "" // TODO: Used for closures, replace with better name?

      let parameterResults = try enumCase.parameters.enumerated().map { idx, parameter in
        let resultName = (parameter.name ?? "arg\(idx)").javaSafeIdentifier
        let translatedResult = try self.translateResult(
          swiftType: parameter.type,
          methodName: methodName,
          resultName: resultName
        )
        return (
          parameter: JavaParameter(name: resultName, type: translatedResult.javaType),
          requiresSwiftArena: translatedResult.conversion.requiresSwiftArena
        )
      }

      let associatedValueTypes = enumCase.parameters.map { param in
        param.type.description
      }.joined(separator: .comma)
      let javaCaseClassName = enumCase.name.firstCharacterUppercased
      let resultType = knownTypes.optionalSugar(
        .tuple(
          enumCase.parameters.map {
            SwiftTupleElement(label: nil, type: $0.type)
          }
        )
      )
      let getAsCaseFunction: ExtractedFunc? =
        if !enumCase.parameters.isEmpty {
          ExtractedFunc(
            module: enumCase.enumType.nominalTypeDecl.moduleName,
            swiftDecl: DeclSyntax("func getAs\(raw: javaCaseClassName)() -> (\(raw: associatedValueTypes))?"),
            name: "getAs\(javaCaseClassName)",
            apiKind: .function,
            functionSignature: .init(
              selfParameter: .instance(convention: .byValue, swiftType: .nominal(enumCase.enumType)),
              parameters: [],
              result: .init(convention: .direct, type: resultType),
              effectSpecifiers: [],
              genericParameters: [],
              genericRequirements: []
            )
          )
        } else {
          nil
        }

      return TranslatedEnumCase(
        name: javaCaseClassName,
        original: enumCase,
        parameters: parameterResults.map(\.parameter),
        getAsCaseFunction: getAsCaseFunction,
        requiresSwiftArena: parameterResults.contains(where: \.requiresSwiftArena)
      )
    }

    func translate(_ decl: ExtractedFunc) throws -> TranslatedFunctionDecl {
      // Java has no `inout`; the thunk would pass a converted temporary, which doesn't compile.
      if decl.functionSignature.parameters.contains(where: { $0.convention == .inout }) {
        throw JavaTranslationError.inoutParametersNotSupported
      }

      let nativeTranslation = NativeJavaTranslation(
        config: self.config,
        javaPackage: self.javaPackage,
        javaClassLookupTable: self.javaClassLookupTable,
        knownTypes: self.knownTypes,
        protocolWrappers: self.protocolWrappers,
        logger: self.logger,
        javaCallbackModules: self.javaCallbackModules,
        closureInterfaceOwner: self.closureInterfaceOwner,
      )

      // Types with no parent will be outputted inside a "module" class.
      let parentName =
        if let parent = decl.parentType?.asNominalTypeDeclaration {
          parent.qualifiedTypeName
        } else {
          SwiftQualifiedTypeName(swiftModuleName)
        }

      // Name.
      let javaName = javaIdentifiers.makeJavaMethodName(decl)

      // A function returning `AsyncStream<T>` or `AsyncThrowingStream<T, _>` is translated as returning `T`, then converted to a stream.
      var resultSignature = decl.functionSignature
      let streamElementType = Self.asyncStreamElementType(decl.functionSignature.result.type)
      if let streamElementType {
        if decl.functionSignature.isAsync || decl.functionSignature.isIsolated || decl.functionSignature.isImplicitlyAsync {
          throw JavaTranslationError.unsupportedSwiftType(decl.functionSignature.result.type)
        }
        resultSignature.result = SwiftResult(convention: .direct, type: streamElementType)
      }
      // A returned closure crosses as the handle of a Swift closure; Java wraps it in a lambda, below.
      let closureResult = Self.closureType(decl.functionSignature.result.type).map { closureType, isOptional in
        var closureType = closureType
        closureType.isEscaping = true
        return (closureType, isOptional)
      }
      if closureResult != nil {
        if decl.functionSignature.isAsync || decl.functionSignature.isIsolated || decl.functionSignature.isImplicitlyAsync {
          throw JavaTranslationError.unsupportedSwiftType(decl.functionSignature.result.type)
        }
        resultSignature.result = SwiftResult(convention: .direct, type: knownTypes.int64)
      }

      // Swift -> Java
      var translatedFunctionSignature = try self.translate(
        functionSignature: resultSignature,
        methodName: javaName,
        parentName: parentName,
      )
      // The declaration's own optionals only: closures and other nested signatures keep `Optional`.
      if config.effectiveOptionalsAsNullable {
        for (idx, parameter) in resultSignature.parameters.enumerated() where Self.isOptional(parameter.type) {
          translatedFunctionSignature.parameters[idx] = nullable(translatedFunctionSignature.parameters[idx])
        }
        if Self.isOptional(resultSignature.result.type) {
          translatedFunctionSignature.result = nullable(translatedFunctionSignature.result, resultName: "result")
        }
      }
      // Java -> Java (native)
      var nativeFunctionSignature = try nativeTranslation.translate(
        functionSignature: resultSignature,
        translatedFunctionSignature: translatedFunctionSignature,
        methodName: javaName,
        parentName: parentName,
      )

      // Closures.
      var funcTypes: [TranslatedFunctionType] = []
      for (idx, param) in decl.functionSignature.parameters.enumerated() {
        // Named like the Java parameter whose type this interface is (see `translateParameters`).
        let parameterName = (param.parameterName ?? "arg\(idx)").javaSafeIdentifier.thunkSafeParameterName

        switch Self.closureType(param.type) {
        case .some((let funcTy, _)):
          var translatedClosure = try translateFunctionType(
            name: parameterName,
            swiftType: funcTy,
            parentName: parentName,
          )
          // Lift the escaping-closure spec off the matching `NativeParameter`
          // onto the `TranslatedFunctionType`. This keeps the wrap-java
          // emission colocated with the decl it belongs to, so the thunk
          // printer can emit the `@JavaInterface` Swift struct alongside
          // the cdecl thunk that references it - no generator-level
          // sink/dict/pre-pass required. `NativeParameter` runs 1:1 with
          // the Swift parameters here (a Swift param can lower to multiple
          // *JavaParameter*s but stays one `NativeParameter`), so indexing
          // by `idx` is correct.
          if idx < nativeFunctionSignature.parameters.count {
            translatedClosure.syntheticClosureType =
              nativeFunctionSignature.parameters[idx].syntheticClosure
          }
          funcTypes.append(translatedClosure)
        case .none:
          break
        }
      }

      var closureHelperClassName = javaName
      if let (closureType, isOptional) = closureResult {
        // A getter returns the closure type its setter takes, so Kotlin sees one property.
        var interfaceName = "result"
        if decl.apiKind == .getter, Self.hasSetter(decl, config: config) {
          closureHelperClassName = "set\(decl.name.firstCharacterUppercased)"
          interfaceName = "newValue"
        }
        let translatedClosure = try translateFunctionType(
          name: interfaceName,
          swiftType: closureType,
          parentName: parentName,
        )
        funcTypes.append(translatedClosure)
        let interfaceType = JavaType.class(
          package: javaPackage,
          name: String.javaQualifiedName(parentName.fullName, closureHelperClassName, interfaceName)
        )
        let nullable = isOptional && config.effectiveOptionalsAsNullable
        translatedFunctionSignature.result = TranslatedResult(
          javaType: isOptional && !nullable ? .optional(interfaceType) : interfaceType,
          nativeJavaType: .long,
          outParameters: [],
          conversion: .swiftClosure(
            .placeholder,
            interfaceType: interfaceType,
            parameters: translatedClosure.parameters.map(\.parameter.type.javaType),
            result: translatedClosure.result.javaType,
            optional: isOptional ? (nullable ? .nullable : .javaOptional) : nil
          )
        )
        nativeFunctionSignature.result = try nativeTranslation.translateSwiftClosureResult(
          closureType,
          isOptional: isOptional
        )
      }

      if streamElementType != nil {
        try self.convertToAsyncStream(
          translatedFunctionSignature: &translatedFunctionSignature,
          nativeFunctionSignature: &nativeFunctionSignature
        )
      }

      // Handle async methods and isolated methods
      if decl.functionSignature.isAsync || decl.functionSignature.isIsolated
        || decl.functionSignature.isImplicitlyAsync
      {
        self.convertToAsync(
          translatedFunctionSignature: &translatedFunctionSignature,
          nativeFunctionSignature: &nativeFunctionSignature,
          originalFunctionSignature: decl.functionSignature,
          mode: config.effectiveAsyncFuncMode,
        )
      }

      // Kotlin's view of the declaration's own parameters and result, after every conversion above.
      let resultIsNullable =
        config.effectiveOptionalsAsNullable && Self.isOptional(decl.functionSignature.result.type)
        && streamElementType == nil
        && !(decl.functionSignature.isAsync || decl.functionSignature.isIsolated || decl.functionSignature.isImplicitlyAsync)
      if let annotation = nullabilityAnnotation(translatedFunctionSignature.result.javaType, nullable: resultIsNullable) {
        translatedFunctionSignature.result.annotations.append(annotation)
      }
      for (idx, parameter) in decl.functionSignature.parameters.enumerated() {
        let nullable = config.effectiveOptionalsAsNullable && Self.isOptional(parameter.type)
        let translated = translatedFunctionSignature.parameters[idx]
        let javaType = translated.parameter.type
        if !javaType.isPrimitive, let annotation = nullabilityAnnotation(javaType.javaType, nullable: nullable) {
          translatedFunctionSignature.parameters[idx] = TranslatedParameter(
            parameter: JavaParameter(
              name: translated.parameter.name,
              type: javaType,
              annotations: translated.parameter.annotations + [annotation]
            ),
            conversion: translated.conversion
          )
        }
      }

      var thrownJavaType: JavaType?
      if case .nominal(let thrown) = decl.functionSignature.thrownTypedError,
        self.errorTypes.contains(thrown.nominalTypeDecl.identity)
      {
        // Only qualify the package when the error type lives in another Java package
        let thrownPackage = moduleJavaPackages[thrown.nominalTypeDecl.moduleName]
        thrownJavaType = .class(
          package: thrownPackage == self.javaPackage ? nil : thrownPackage,
          name: thrown.nominalTypeDecl.qualifiedName
        )
      }

      return TranslatedFunctionDecl(
        name: javaName,
        isStatic: decl.isStatic || decl.isClass || !decl.hasParent || decl.isInitializer,
        isThrowing: decl.isThrowing,
        thrownJavaType: thrownJavaType,
        isAsync: decl.isAsync,
        isIsolated: decl.isIsolated,
        isImplicitlyAsync: decl.functionSignature.isImplicitlyAsync,
        nativeFunctionName: "$\(javaName)",
        parentName: parentName,
        closureHelperClassName: closureHelperClassName,
        functionTypes: funcTypes,
        translatedFunctionSignature: translatedFunctionSignature,
        nativeFunctionSignature: nativeFunctionSignature,
      )
    }

    /// Translate Swift closure type to Java functional interface.
    func translateFunctionType(
      name: String,
      swiftType: SwiftFunctionType,
      parentName: SwiftQualifiedTypeName,
    ) throws -> TranslatedFunctionType {
      var translatedParams: [TranslatedParameter] = []

      for (i, param) in swiftType.parameters.enumerated() {
        let paramName = (param.parameterName ?? "_\(i)").javaSafeIdentifier
        translatedParams.append(
          try translateParameter(
            swiftType: param.type,
            parameterName: paramName,
            methodName: name,
            parentName: parentName,
            genericParameters: [],
            genericRequirements: [],
            parameterPosition: nil,
          )
        )
      }

      var translatedResult = try translateResult(swiftType: swiftType.resultType, methodName: name)
      // An async closure implemented in Java returns a future, which Swift awaits.
      if swiftType.isAsync {
        translatedResult.javaType = .completableFuture(translatedResult.javaType)
      }

      return TranslatedFunctionType(
        name: name,
        parameters: translatedParams,
        result: translatedResult,
        swiftType: swiftType,
      )
    }

    func translate(
      functionSignature: SwiftFunctionSignature,
      methodName: String,
      parentName: SwiftQualifiedTypeName,
    ) throws -> TranslatedFunctionSignature {
      let parameters = try translateParameters(
        functionSignature.parameters.map { ($0.parameterName, $0.type) },
        methodName: methodName,
        parentName: parentName,
        genericParameters: functionSignature.genericParameters,
        genericRequirements: functionSignature.genericRequirements,
      )

      // 'self'
      let selfParameter = try self.translateSelfParameter(
        functionSignature.selfParameter,
        methodName: methodName,
        parentName: parentName,
        genericParameters: functionSignature.genericParameters,
        genericRequirements: functionSignature.genericRequirements,
      )

      let selfTypeParameter = try self.translateSelfTypeParameter(
        functionSignature.selfParameter,
        methodName: methodName,
        parentName: parentName,
        genericParameters: functionSignature.genericParameters,
        genericRequirements: functionSignature.genericRequirements,
      )

      var exceptions: [JavaExceptionType] = []

      if functionSignature.parameters.contains(where: \.type.isArchDependingInteger) {
        exceptions.append(.integerOverflow)
      }

      let resultType = try translateResult(
        swiftType: functionSignature.result.type,
        methodName: methodName,
        genericParameters: functionSignature.genericParameters,
        genericRequirements: functionSignature.genericRequirements,
      )

      return TranslatedFunctionSignature(
        selfParameter: selfParameter,
        selfTypeParameter: selfTypeParameter,
        parameters: parameters,
        result: resultType,
        exceptions: exceptions,
      )
    }

    func translateParameters(
      _ parameters: [(name: String?, type: SwiftType)],
      methodName: String,
      parentName: SwiftQualifiedTypeName,
      genericParameters: [SwiftGenericParameterDeclaration],
      genericRequirements: [SwiftGenericRequirement],
    ) throws -> [TranslatedParameter] {
      try parameters.enumerated().map { idx, param in
        let parameterName = (param.name ?? "arg\(idx)").javaSafeIdentifier.thunkSafeParameterName
        return try translateParameter(
          swiftType: param.type,
          parameterName: parameterName,
          methodName: methodName,
          parentName: parentName,
          genericParameters: genericParameters,
          genericRequirements: genericRequirements,
          parameterPosition: idx,
        )
      }
    }

    func translateSelfParameter(
      _ selfParameter: SwiftSelfParameter?,
      methodName: String,
      parentName: SwiftQualifiedTypeName,
      genericParameters: [SwiftGenericParameterDeclaration],
      genericRequirements: [SwiftGenericRequirement],
    ) throws -> TranslatedParameter? {
      // 'self'
      if case .instance(_, let swiftType) = selfParameter {
        return try self.translateParameter(
          swiftType: swiftType,
          parameterName: "selfPointer",
          methodName: methodName,
          parentName: parentName,
          genericParameters: genericParameters,
          genericRequirements: genericRequirements,
          parameterPosition: nil,
        )
      } else {
        return nil
      }
    }

    func translateSelfTypeParameter(
      _ selfParameter: SwiftSelfParameter?,
      methodName: String,
      parentName: SwiftQualifiedTypeName,
      genericParameters: [SwiftGenericParameterDeclaration],
      genericRequirements: [SwiftGenericRequirement],
    ) throws -> TranslatedParameter? {
      guard let selfParameter else {
        return nil
      }
      let isGeneric = selfParameter.selfType.asNominalTypeDeclaration?.isGeneric == true
      let isProtocol = selfParameter.selfType.asNominalType?.isProtocol == true

      guard isGeneric || isProtocol else {
        return nil
      }

      switch selfParameter {
      case .instance:
        return TranslatedParameter(
          parameter: JavaParameter(name: "selfTypePointer", type: .long),
          conversion: .typeMetadataAddress(.placeholder),
        )
      case .staticMethod, .classMethod, .initializer:
        return TranslatedParameter(
          parameter: JavaParameter(name: "selfTypePointer", type: .long),
          conversion: .constant("$typeMetadataAddressDowncall()"),
        )
      }
    }

    func translateParameter(
      swiftType: SwiftType,
      parameterName: String,
      methodName: String,
      parentName: SwiftQualifiedTypeName,
      genericParameters: [SwiftGenericParameterDeclaration],
      genericRequirements: [SwiftGenericRequirement],
      parameterPosition: Int?,
    ) throws -> TranslatedParameter {

      // If the result type should cause any annotations on the method, include them here.
      let parameterAnnotations: [JavaAnnotation] = getJavaTypeAnnotations(swiftType: swiftType, config: config)

      // A Swift error is a Java `Throwable`.
      if swiftType.isSwiftError {
        return TranslatedParameter(
          parameter: JavaParameter(name: parameterName, type: .javaLangThrowable, annotations: parameterAnnotations),
          conversion: .placeholder
        )
      }

      switch swiftType {
      case .nominal(let nominalType):
        let nominalTypeName = nominalType.nominalTypeDecl.qualifiedName

        if let knownType = nominalType.asKnownType {
          switch knownType {
          case .optional(let wrapped):
            if wrapped.isSwiftError {
              return TranslatedParameter(
                parameter: JavaParameter(
                  name: parameterName,
                  type: .optional(.javaLangThrowable),
                  annotations: parameterAnnotations
                ),
                conversion: .method(.placeholder, function: "orElse", arguments: [.constant("null")])
              )
            }
            if let (functionType, _) = Self.closureType(swiftType) {
              let closure = translateFunctionParameter(
                swiftType: .function(functionType),
                functionType: functionType,
                parameterName: parameterName,
                methodName: methodName,
                parentName: parentName,
                parameterAnnotations: parameterAnnotations
              )
              return TranslatedParameter(
                parameter: JavaParameter(
                  name: parameterName,
                  type: .optional(closure.parameter.type.javaType),
                  annotations: parameterAnnotations
                ),
                conversion: .method(.placeholder, function: "orElse", arguments: [.constant("null")])
              )
            }
            return try translateOptionalParameter(
              wrappedType: wrapped,
              parameterName: parameterName,
              genericParameters: genericParameters,
              genericRequirements: genericRequirements,
            )

          case .array(let elementType):
            return try translateArrayParameter(
              elementType: elementType,
              parameterName: parameterName,
              genericParameters: genericParameters,
              genericRequirements: genericRequirements,
            )

          case .dictionary(let keyType, let valueType):
            return try translateDictionaryParameter(
              keyType: keyType,
              valueType: valueType,
              parameterName: parameterName,
              genericParameters: genericParameters,
              genericRequirements: genericRequirements,
            )

          case .set(let elementType):
            return try translateSetParameter(
              elementType: elementType,
              parameterName: parameterName,
              genericParameters: genericParameters,
              genericRequirements: genericRequirements,
            )

          case .foundationDate where !config.effectiveFoundationTypesAsJavaTypes,
            .essentialsDate where !config.effectiveFoundationTypesAsJavaTypes,
            .foundationData where !config.effectiveFoundationTypesAsJavaTypes,
            .essentialsData where !config.effectiveFoundationTypesAsJavaTypes,
            .foundationURL where !config.effectiveFoundationTypesAsJavaTypes,
            .essentialsURL where !config.effectiveFoundationTypesAsJavaTypes:
            break // Handled as wrapped struct

          case .unsafeRawBufferPointer, .unsafeMutableRawBufferPointer:
            return TranslatedParameter(
              parameter: JavaParameter(name: parameterName, type: .array(.byte)),
              conversion: .placeholder
            )

          case .foundationUUID, .essentialsUUID:
            return TranslatedParameter(
              parameter: JavaParameter(name: parameterName, type: .javaUtilUUID),
              conversion: .method(.placeholder, function: "toString"),
            )

          default:
            guard let javaType = JNIJavaTypeTranslator.translate(knownType: knownType.kind, config: self.config) else {
              throw JavaTranslationError.unsupportedSwiftType(swiftType)
            }

            return TranslatedParameter(
              parameter: JavaParameter(name: parameterName, type: javaType, annotations: parameterAnnotations),
              conversion: .placeholder,
            )
          }
        }

        if nominalType.isSwiftJavaWrapper {
          guard let javaType = nominalTypeName.parseJavaClassFromSwiftJavaName(in: self.javaClassLookupTable) else {
            throw JavaTranslationError.wrappedJavaClassTranslationNotProvided(swiftType)
          }

          return TranslatedParameter(
            parameter: JavaParameter(name: parameterName, type: javaType, annotations: parameterAnnotations),
            conversion: .placeholder,
          )
        }

        let javaType = JavaType.class(
          package: moduleJavaPackages[nominalType.nominalTypeDecl.moduleName],
          name: nominalTypeName,
          typeParameters: try nominalType.genericArguments.map { swiftType in
            try translateGenericTypeParameter(
              swiftType,
              genericParameters: genericParameters,
              genericRequirements: genericRequirements,
            )
          },
        )

        // We assume this is a JExtract class.
        return TranslatedParameter(
          parameter: JavaParameter(
            name: parameterName,
            type: .concrete(javaType),
            annotations: parameterAnnotations,
          ),
          conversion: .valueMemoryAddress(.placeholder),
        )

      case .tuple([]):
        return TranslatedParameter(
          parameter: JavaParameter(name: parameterName, type: .void, annotations: parameterAnnotations),
          conversion: .placeholder,
        )

      case .function(let functionType):
        return translateFunctionParameter(
          swiftType: swiftType,
          functionType: functionType,
          parameterName: parameterName,
          methodName: methodName,
          parentName: parentName,
          parameterAnnotations: parameterAnnotations
        )

      case .opaque(let proto), .existential(let proto):
        guard let parameterPosition else {
          fatalError("Cannot extract opaque or existential type that is not a parameter: \(proto)")
        }

        return try translateProtocolParameter(
          protocolType: proto,
          parameterName: parameterName,
          javaGenericName: "_T\(parameterPosition)",
          genericParameters: genericParameters,
          genericRequirements: genericRequirements,
        )

      case .genericParameter(let generic):
        if let concreteTy = swiftType.typeIn(
          genericParameters: genericParameters,
          genericRequirements: genericRequirements,
        ) {
          return try translateProtocolParameter(
            protocolType: concreteTy,
            parameterName: parameterName,
            javaGenericName: generic.name,
            genericParameters: genericParameters,
            genericRequirements: genericRequirements,
          )
        }

        throw JavaTranslationError.unsupportedSwiftType(swiftType)

      case .metatype:
        return TranslatedParameter(
          parameter: JavaParameter(name: parameterName, type: .long),
          conversion: .typeMetadataAddress(.placeholder),
        )

      case .tuple(let elements) where elements.count == 1:
        return try translateParameter(
          swiftType: elements[0].type,
          parameterName: parameterName,
          methodName: methodName,
          parentName: parentName,
          genericParameters: genericParameters,
          genericRequirements: genericRequirements,
          parameterPosition: parameterPosition,
        )

      case .tuple(let elements) where !elements.isEmpty:
        return try translateTupleParameter(
          elements: elements,
          parameterName: parameterName,
          methodName: methodName,
          parentName: parentName,
          genericParameters: genericParameters,
          genericRequirements: genericRequirements,
          parameterPosition: parameterPosition,
        )

      case .tuple:
        throw JavaTranslationError.emptyTuple()
      case .composite, .inlineArray:
        throw JavaTranslationError.unsupportedSwiftType(swiftType)
      }
    }

    func translateTupleParameter(
      elements: [SwiftTupleElement],
      parameterName: String,
      methodName: String,
      parentName: SwiftQualifiedTypeName,
      genericParameters: [SwiftGenericParameterDeclaration],
      genericRequirements: [SwiftGenericRequirement],
      parameterPosition: Int?,
    ) throws -> TranslatedParameter {
      var elementJavaTypes: [JavaType] = []

      // Generate a conversion that extracts each element from the Tuple
      var elementConversions: [JavaNativeConversionStep] = []
      for (idx, element) in elements.enumerated() {
        let elementTranslated = try translateParameter(
          swiftType: element.type,
          parameterName: "\(parameterName)_\(idx)",
          methodName: methodName,
          parentName: parentName,
          genericParameters: genericParameters,
          genericRequirements: genericRequirements,
          parameterPosition: parameterPosition,
        )

        // Extract the element from the tuple using .$N field access
        let extraction = JavaNativeConversionStep.replacingPlaceholder(
          elementTranslated.conversion,
          placeholder: "\(parameterName).$\(idx)",
        )
        elementConversions.append(extraction)
        elementJavaTypes.append(elementTranslated.parameter.type.javaType)
      }

      let javaType: JavaType = .tuple(elementTypes: elementJavaTypes)

      return TranslatedParameter(
        parameter: JavaParameter(
          name: parameterName,
          type: javaType,
        ),
        conversion: .commaSeparated(elementConversions),
      )
    }

    /// The element type of an `AsyncStream<Element>` or `AsyncThrowingStream<Element, Failure>`, or nil.
    static func asyncStreamElementType(_ type: SwiftType) -> SwiftType? {
      guard case .nominal(let nominal) = type else {
        return nil
      }
      switch nominal.asKnownType {
      case .asyncStream(let element), .asyncThrowingStream(let element):
        return element
      default:
        return nil
      }
    }

    /// Turns a function translated as returning `T` into one returning a `SwiftAsyncStream<T>`: Java
    /// passes a stream for Swift to attach the `AsyncStream` to, and maps each delivered element
    /// with the conversion it would apply to a `T` result.
    func convertToAsyncStream(
      translatedFunctionSignature: inout TranslatedFunctionSignature,
      nativeFunctionSignature: inout NativeFunctionSignature
    ) throws {
      let element = translatedFunctionSignature.result
      let nativeElement = nativeFunctionSignature.result
      // Elements arrive one at a time as a single Java value; indirect returns (out parameters) don't fit.
      guard element.outParameters.isEmpty, nativeElement.outParameters.isEmpty, !nativeElement.javaType.isVoid else {
        throw JavaTranslationError.asyncStreamElementNotSupported
      }
      let nativeStreamType = JavaType.swiftAsyncStream(nativeElement.javaType)

      translatedFunctionSignature.result = TranslatedResult(
        javaType: .swiftAsyncStream(element.javaType),
        nativeJavaType: .void,
        annotations: element.annotations,
        outParameters: [OutParameter(name: "stream$", type: nativeStreamType, allocation: .new)],
        conversion: .method(
          .constant("stream$"),
          function: "map",
          arguments: [
            .lambda(
              args: ["element$"],
              body: .replacingPlaceholder(element.conversion, placeholder: "element$")
            )
          ]
        )
      )

      nativeFunctionSignature.result.conversion = .attachAsyncStream(
        elementConversion: nativeElement.conversion,
        elementJavaType: nativeElement.javaType
      )
      nativeFunctionSignature.result.javaType = .void
      nativeFunctionSignature.result.outParameters.append(.init(name: "result_stream", type: nativeStreamType))
    }

    func convertToAsync(
      translatedFunctionSignature: inout TranslatedFunctionSignature,
      nativeFunctionSignature: inout NativeFunctionSignature,
      originalFunctionSignature: SwiftFunctionSignature,
      mode: JExtractAsyncFuncMode,
    ) {
      // Update translated function
      let nativeFutureType: JavaType
      let translatedFutureType: JavaType
      let completeMethodID: String
      let completeExceptionallyMethodID: String

      switch mode {
      case .completableFuture:
        nativeFutureType = .completableFuture(nativeFunctionSignature.result.javaType)
        translatedFutureType = .completableFuture(translatedFunctionSignature.result.javaType)
        completeMethodID = "_JNIMethodIDCache.CompletableFuture.complete"
        completeExceptionallyMethodID = "_JNIMethodIDCache.CompletableFuture.completeExceptionally"

      case .legacyFuture:
        nativeFutureType = .simpleCompletableFuture(nativeFunctionSignature.result.javaType)
        translatedFutureType = .future(translatedFunctionSignature.result.javaType)
        completeMethodID = "_JNIMethodIDCache.SimpleCompletableFuture.complete"
        completeExceptionallyMethodID = "_JNIMethodIDCache.SimpleCompletableFuture.completeExceptionally"
      }

      let futureOutParameter = OutParameter(
        name: "future$",
        type: nativeFutureType,
        allocation: .new,
      )

      let result = translatedFunctionSignature.result
      let convertedFuture = JavaNativeConversionStep.method(
        .constant("future$"),
        function: "thenApply",
        arguments: [
          .lambda(
            args: ["futureResult$"],
            body: .replacingPlaceholder(result.conversion, placeholder: "futureResult$")
          )
        ]
      )
      translatedFunctionSignature.result = TranslatedResult(
        javaType: translatedFutureType,
        nativeJavaType: .void,
        annotations: result.annotations,
        outParameters: result.outParameters + [futureOutParameter],
        // Cancelling the returned (derived) future must reach `future$`, which the Swift task watches.
        conversion: mode == .completableFuture
          ? .method(
            .constant("org.swift.swiftkit.core.CompletableFutureCancellation"),
            function: "forwardCancellation",
            arguments: [convertedFuture, .constant("future$")]
          )
          : convertedFuture
      )

      // Update native function
      nativeFunctionSignature.result.conversion = .asyncCompleteFuture(
        swiftFunctionResultType: originalFunctionSignature.result.type,
        nativeFunctionSignature: nativeFunctionSignature,
        isThrowing: originalFunctionSignature.isThrowing || originalFunctionSignature.isImplicitlyThrowing,
        completeMethodID: completeMethodID,
        completeExceptionallyMethodID: completeExceptionallyMethodID,
        cancelsTaskWithFuture: mode == .completableFuture,
      )
      nativeFunctionSignature.result.javaType = .void
      nativeFunctionSignature.result.outParameters.append(.init(name: "result_future", type: nativeFutureType))
    }

    func translateFunctionParameter(
      swiftType: SwiftType,
      functionType: SwiftFunctionType,
      parameterName: String,
      methodName: String,
      parentName: SwiftQualifiedTypeName,
      parameterAnnotations: [JavaAnnotation]
    ) -> TranslatedParameter {
      let interfacejavaType =
        if let known = KnownJavaFunctionalInterface.find(functionType, closureMethodName: config.effectiveClosureMethodName) {
          known.javaType
        } else {
          JavaType.class(
            package: closureInterfaceOwner?.javaPackage ?? javaPackage,
            name: String.javaQualifiedName(
              (closureInterfaceOwner?.typeName ?? parentName).fullName,
              methodName,
              parameterName
            )
          )
        }

      return TranslatedParameter(
        parameter: JavaParameter(
          name: parameterName,
          type: interfacejavaType,
          annotations: parameterAnnotations,
        ),
        conversion: .placeholder,
      )
    }

    func translateProtocolParameter(
      protocolType: SwiftType,
      parameterName: String,
      javaGenericName: String,
      genericParameters: [SwiftGenericParameterDeclaration],
      genericRequirements: [SwiftGenericRequirement],
    ) throws -> TranslatedParameter {
      switch protocolType {
      case .nominal:
        return try translateProtocolParameter(
          protocolTypes: [protocolType],
          parameterName: parameterName,
          javaGenericName: javaGenericName,
          genericParameters: genericParameters,
          genericRequirements: genericRequirements,
        )

      case .composite(let types):
        return try translateProtocolParameter(
          protocolTypes: types,
          parameterName: parameterName,
          javaGenericName: javaGenericName,
          genericParameters: genericParameters,
          genericRequirements: genericRequirements,
        )

      default:
        throw JavaTranslationError.unsupportedSwiftType(protocolType)
      }
    }

    private func translateProtocolParameter(
      protocolTypes: [SwiftType],
      parameterName: String,
      javaGenericName: String,
      genericParameters: [SwiftGenericParameterDeclaration],
      genericRequirements: [SwiftGenericRequirement],
    ) throws -> TranslatedParameter {
      let javaProtocolTypes = try protocolTypes.map {
        try translateGenericTypeParameter(
          $0,
          genericParameters: genericParameters,
          genericRequirements: genericRequirements,
        )
      }

      // We just pass down the jobject
      return TranslatedParameter(
        parameter: JavaParameter(
          name: parameterName,
          type: .generic(name: javaGenericName, extends: javaProtocolTypes),
          annotations: [],
        ),
        conversion: .placeholder,
      )
    }

    /// The closure type of a closure or optional closure. An optional closure is escaping: it can be stored, and
    /// only escaping closure types get their own functional interface.
    static func closureType(_ type: SwiftType) -> (SwiftFunctionType, isOptional: Bool)? {
      switch type {
      case .function(let functionType):
        return (functionType, false)
      case .nominal(let nominal):
        guard case .optional(.function(var functionType)) = nominal.asKnownType else {
          return nil
        }
        functionType.isEscaping = true
        return (functionType, true)
      default:
        return nil
      }
    }

    /// Whether the property of this getter also has a setter.
    static func hasSetter(_ getter: ExtractedFunc, config: Configuration) -> Bool {
      guard let variable = getter.swiftDecl.as(VariableDeclSyntax.self), let binding = variable.bindings.first else {
        return false
      }
      return variable.supportedAccessorKinds(
        binding: binding,
        minimumAccessLevel: config.effectiveMinimumInputAccessLevelMode
      ).contains(.set)
    }

    /// The configured `nullableAnnotation` or `nonNullAnnotation` for a reference type.
    func nullabilityAnnotation(_ javaType: JavaType, nullable: Bool) -> JavaAnnotation? {
      if javaType.isPrimitive {
        return nil
      }
      return (nullable ? config.nullableAnnotation : config.nonNullAnnotation).map { JavaAnnotation(className: $0) }
    }

    static func isOptional(_ type: SwiftType) -> Bool {
      if case .nominal(let nominal) = type, nominal.nominalTypeDecl.knownTypeKind == .optional {
        return true
      }
      return false
    }

    /// The wrapped Java type of a Java optional type, boxed, with the method that unwraps a present value.
    private func nullableType(ofOptional type: JavaType) -> (type: JavaType, getter: String)? {
      guard case .class(_, let name, let typeParameters) = type else {
        return nil
      }
      // Spelled as one class name, such as `Optional<Boolean>` or `Optional<java.net.URI>`. The dots in
      // the latter split it into a package and a name, so match the whole spelling.
      let spelling = type.description
      if typeParameters.isEmpty, spelling.hasPrefix("Optional<"), spelling.hasSuffix(">") {
        return (JavaType(className: String(spelling.dropFirst("Optional<".count).dropLast())), "get")
      }
      switch name {
      case "OptionalLong": return (.class(package: "java.lang", name: "Long"), "getAsLong")
      case "OptionalInt": return (.class(package: "java.lang", name: "Integer"), "getAsInt")
      case "OptionalDouble": return (.class(package: "java.lang", name: "Double"), "getAsDouble")
      case "Optional" where typeParameters.count == 1: return (typeParameters[0], "get")
      default: return nil
      }
    }

    /// With `optionalsAsNullable`, an optional parameter takes the wrapped type, `null` for `nil`, and
    /// makes the `Optional` the translated conversion expects.
    func nullable(_ parameter: TranslatedParameter) -> TranslatedParameter {
      guard let (wrapped, _) = nullableType(ofOptional: parameter.parameter.type.javaType),
        case .class(_, let optionalClass, _) = parameter.parameter.type.javaType
      else {
        return parameter
      }
      let name = parameter.parameter.name
      let optional =
        switch optionalClass {
        case "OptionalLong", "OptionalInt", "OptionalDouble":
          "(\(name) == null ? \(optionalClass).empty() : \(optionalClass).of(\(name)))"
        default:
          "Optional.ofNullable(\(name))"
        }
      return TranslatedParameter(
        parameter: JavaParameter(name: name, type: wrapped, annotations: parameter.parameter.annotations),
        conversion: .replacingPlaceholder(parameter.conversion, placeholder: optional)
      )
    }

    /// With `optionalsAsNullable`, an optional result is its wrapped value, or `null` for `nil`.
    func nullable(_ result: TranslatedResult, resultName: String) -> TranslatedResult {
      guard let (wrapped, getter) = nullableType(ofOptional: result.javaType) else {
        return result
      }
      let optional = "\(resultName)$optional"
      var nullable = result
      nullable.javaType = wrapped
      nullable.conversion = .ternary(
        .method(.placeToVar(result.conversion, name: optional, type: result.javaType), function: "isPresent"),
        thenExp: .method(.constant(optional), function: getter),
        elseExp: .constant("null")
      )
      return nullable
    }

    func translateOptionalParameter(
      wrappedType swiftType: SwiftType,
      parameterName: String,
      genericParameters: [SwiftGenericParameterDeclaration],
      genericRequirements: [SwiftGenericRequirement],
    ) throws -> TranslatedParameter {
      let parameterAnnotations: [JavaAnnotation] = getJavaTypeAnnotations(swiftType: swiftType, config: config)

      switch swiftType {
      case .nominal(let nominalType):
        let nominalTypeName = nominalType.nominalTypeDecl.qualifiedName

        if let knownType = nominalType.nominalTypeDecl.knownTypeKind {
          switch knownType {
          case .foundationDate where !config.effectiveFoundationTypesAsJavaTypes,
            .essentialsDate where !config.effectiveFoundationTypesAsJavaTypes:
            // Handled as wrapped struct
            break

          case .foundationData where !config.effectiveFoundationTypesAsJavaTypes,
            .essentialsData where !config.effectiveFoundationTypesAsJavaTypes:
            // Handled as wrapped struct
            break

          default:
            guard let javaType = JNIJavaTypeTranslator.translate(knownType: knownType, config: self.config) else {
              throw JavaTranslationError.unsupportedSwiftType(swiftType)
            }

            guard let translatedClass = javaType.optionalType, let placeholderValue = javaType.optionalPlaceholderValue
            else {
              throw JavaTranslationError.unsupportedSwiftType(swiftType)
            }

            return TranslatedParameter(
              parameter: JavaParameter(
                name: parameterName,
                type: JavaType(className: translatedClass),
                annotations: parameterAnnotations,
              ),
              conversion: .commaSeparated([
                .isOptionalPresent,
                .method(.placeholder, function: "orElse", arguments: [.constant(placeholderValue)]),
              ]),
            )
          }
        }

        if nominalType.isSwiftJavaWrapper {
          guard let javaType = nominalTypeName.parseJavaClassFromSwiftJavaName(in: self.javaClassLookupTable) else {
            throw JavaTranslationError.wrappedJavaClassTranslationNotProvided(swiftType)
          }

          return TranslatedParameter(
            parameter: JavaParameter(
              name: parameterName,
              type: .optional(javaType),
              annotations: parameterAnnotations,
            ),
            conversion: .method(
              .placeholder,
              function: "orElse",
              arguments: [.constant("null")],
            ),
          )
        }

        // Assume JExtract imported class
        let javaType = try translateGenericTypeParameter(
          swiftType,
          genericParameters: genericParameters,
          genericRequirements: genericRequirements,
        )
        return TranslatedParameter(
          parameter: JavaParameter(
            name: parameterName,
            type: .optional(javaType),
            annotations: parameterAnnotations,
          ),
          conversion: .method(
            .method(.placeholder, function: "map", arguments: [.constant("\(javaType)::$memoryAddress")]),
            function: "orElse",
            arguments: [.constant("0L")],
          ),
        )
      default:
        throw JavaTranslationError.unsupportedSwiftType(swiftType)
      }
    }

    func translateResult(
      swiftType: SwiftType,
      methodName: String,
      resultName: String = "result",
      genericParameters: [SwiftGenericParameterDeclaration] = [],
      genericRequirements: [SwiftGenericRequirement] = [],
    ) throws -> TranslatedResult {
      // If the result type should cause any annotations on the method, include them here.
      let resultAnnotations: [JavaAnnotation] = getJavaTypeAnnotations(swiftType: swiftType, config: config)

      // A Swift error is a Java `Throwable`, `null` for `nil`.
      if swiftType.isSwiftError {
        return TranslatedResult(
          javaType: .javaLangThrowable,
          nativeJavaType: .javaLangThrowable,
          annotations: resultAnnotations,
          outParameters: [],
          conversion: .placeholder
        )
      }

      switch swiftType {
      case .nominal(let nominalType):
        let nominalTypeName = nominalType.nominalTypeDecl.qualifiedName
        if let knownType = nominalType.asKnownType {
          switch knownType {
          case .optional(let wrapped) where wrapped.isSwiftError:
            return TranslatedResult(
              javaType: .optional(.javaLangThrowable),
              nativeJavaType: .javaLangThrowable,
              annotations: resultAnnotations,
              outParameters: [],
              conversion: .method(.constant("java.util.Optional"), function: "ofNullable", arguments: [.placeholder])
            )

          case .optional(let wrapped):
            return try translateOptionalResult(
              wrappedType: wrapped,
              methodName: methodName,
              resultName: resultName,
              genericParameters: genericParameters,
              genericRequirements: genericRequirements,
            )

          case .array(let element):
            return try translateArrayResult(
              elementType: element,
              genericParameters: genericParameters,
              genericRequirements: genericRequirements,
            )

          case .dictionary(let key, let value):
            return try translateDictionaryResult(
              keyType: key,
              valueType: value,
              genericParameters: genericParameters,
              genericRequirements: genericRequirements,
            )

          case .set(let element):
            return try translateSetResult(
              elementType: element,
              genericParameters: genericParameters,
              genericRequirements: genericRequirements,
            )

          case .foundationDate where !config.effectiveFoundationTypesAsJavaTypes,
            .essentialsDate where !config.effectiveFoundationTypesAsJavaTypes,
            .foundationData where !config.effectiveFoundationTypesAsJavaTypes,
            .essentialsData where !config.effectiveFoundationTypesAsJavaTypes,
            .foundationURL where !config.effectiveFoundationTypesAsJavaTypes,
            .essentialsURL where !config.effectiveFoundationTypesAsJavaTypes:
            // Handled as wrapped struct
            break

          case .foundationUUID, .essentialsUUID:
            return TranslatedResult(
              javaType: .javaUtilUUID,
              nativeJavaType: .javaLangString,
              outParameters: [],
              conversion: .method(
                .constant("java.util.UUID"),
                function: "fromString",
                arguments: [.placeholder],
              ),
            )

          default:
            guard let javaType = JNIJavaTypeTranslator.translate(knownType: knownType.kind, config: self.config) else {
              throw JavaTranslationError.unsupportedSwiftType(swiftType)
            }

            return TranslatedResult(
              javaType: javaType,
              nativeJavaType: javaType,
              annotations: resultAnnotations,
              outParameters: [],
              conversion: .placeholder,
            )
          }
        }

        if nominalType.isSwiftJavaWrapper {
          guard let javaType = nominalTypeName.parseJavaClassFromSwiftJavaName(in: self.javaClassLookupTable) else {
            throw JavaTranslationError.wrappedJavaClassTranslationNotProvided(swiftType)
          }
          return TranslatedResult(
            javaType: javaType,
            nativeJavaType: javaType,
            annotations: resultAnnotations,
            outParameters: [],
            conversion: .placeholder
          )
        }

        let javaType = JavaType.class(
          package: moduleJavaPackages[nominalType.nominalTypeDecl.moduleName],
          name: nominalType.nominalTypeDecl.qualifiedName,
          typeParameters: try nominalType.genericArguments.map { swiftType in
            try translateGenericTypeParameter(
              swiftType,
              genericParameters: genericParameters,
              genericRequirements: genericRequirements,
            )
          },
        )

        // We assume this is a JExtract class.
        if nominalType.nominalTypeDecl.isGeneric {
          return TranslatedResult(
            javaType: javaType,
            nativeJavaType: .void,
            annotations: resultAnnotations,
            outParameters: [.init(name: resultName, type: ._OutSwiftGenericInstance, allocation: .new)],
            conversion: .wrapMemoryAddressUnsafe(
              .commaSeparated([
                .member(.constant(resultName), field: "selfPointer"),
                .member(.constant(resultName), field: "selfTypePointer"),
              ]),
              javaType
            )
          )
        } else {
          return TranslatedResult(
            javaType: javaType,
            nativeJavaType: .long,
            annotations: resultAnnotations,
            outParameters: [],
            conversion: .wrapMemoryAddressUnsafe(.placeholder, javaType),
          )
        }

      case .tuple([]):
        return TranslatedResult(javaType: .void, nativeJavaType: .void, outParameters: [], conversion: .placeholder)

      case .tuple(let elements) where elements.count == 1:
        return try translateResult(
          swiftType: elements[0].type,
          methodName: methodName,
          resultName: resultName,
          genericParameters: genericParameters,
          genericRequirements: genericRequirements,
        )

      case .tuple(let elements) where !elements.isEmpty:
        return try translateTupleResult(
          methodName: methodName,
          elements: elements,
          resultName: resultName,
          genericParameters: genericParameters,
          genericRequirements: genericRequirements,
        )

      case .opaque(let proto), .existential(let proto):
        guard case .nominal(let protoNominalType) = proto, protoNominalType.isProtocol else {
          throw JavaTranslationError.cannotReturnNonExtractedProtocol(proto)
        }

        let interfaceJavaType = JavaType.class(
          package: moduleJavaPackages[protoNominalType.nominalTypeDecl.moduleName],
          name: protoNominalType.nominalTypeDecl.qualifiedName,
        )
        let boxJavaType = JavaType.class(
          package: moduleJavaPackages[protoNominalType.nominalTypeDecl.moduleName],
          name: protoNominalType.nominalTypeDecl.javaExistentialBoxName,
        )

        return TranslatedResult(
          javaType: interfaceJavaType,
          nativeJavaType: .void,
          annotations: resultAnnotations,
          outParameters: [.init(name: resultName, type: ._OutSwiftGenericInstance, allocation: .new)],
          conversion: .wrapMemoryAddressUnsafe(
            .commaSeparated([
              .member(.constant(resultName), field: "selfPointer"),
              .member(.constant(resultName), field: "selfTypePointer"),
            ]),
            boxJavaType
          )
        )

      case .metatype, .tuple, .function, .genericParameter, .composite, .inlineArray:
        throw JavaTranslationError.unsupportedSwiftType(swiftType)
      }
    }

    private func translateGenericTypeParameter(
      _ swiftType: SwiftType,
      genericParameters: [SwiftGenericParameterDeclaration],
      genericRequirements: [SwiftGenericRequirement],
    ) throws -> JavaType {
      if swiftType.isSwiftError {
        return .javaLangThrowable
      }

      switch swiftType {
      case .nominal(let nominalType):
        let nominalTypeName = nominalType.nominalTypeDecl.qualifiedName

        if let knownType = nominalType.asKnownType {
          switch knownType {
          case .optional(let wrapped):
            if let wrappedKnownKind = wrapped.asNominalTypeDeclaration?.knownTypeKind,
              let javaType = JNIJavaTypeTranslator.translate(knownType: wrappedKnownKind, config: self.config),
              let optionalType = javaType.optionalType
            {
              return .class(package: nil, name: optionalType)
            }

            let wrappedType = try translateGenericTypeParameter(
              wrapped,
              genericParameters: genericParameters,
              genericRequirements: genericRequirements,
            )
            return .optional(wrappedType)

          case .array(let element):
            let elementJavaType = try translateGenericTypeParameter(
              element,
              genericParameters: genericParameters,
              genericRequirements: genericRequirements,
            )
            return .array(elementJavaType)

          case .dictionary(let key, let value):
            let keyJavaType = try translateGenericTypeParameter(
              key,
              genericParameters: genericParameters,
              genericRequirements: genericRequirements,
            )
            let valueJavaType = try translateGenericTypeParameter(
              value,
              genericParameters: genericParameters,
              genericRequirements: genericRequirements,
            )
            return .swiftDictionaryMap(keyJavaType, valueJavaType)

          case .set(let element):
            let elementJavaType = try translateGenericTypeParameter(
              element,
              genericParameters: genericParameters,
              genericRequirements: genericRequirements,
            )
            return .swiftSet(elementJavaType)

          case .foundationDate where !config.effectiveFoundationTypesAsJavaTypes,
            .essentialsDate where !config.effectiveFoundationTypesAsJavaTypes:
            return .class(package: nil, name: "Date")

          case .foundationData where !config.effectiveFoundationTypesAsJavaTypes,
            .essentialsData where !config.effectiveFoundationTypesAsJavaTypes:
            return .class(package: nil, name: "Data")

          case .foundationDataProtocol, .essentialsDataProtocol:
            return .class(package: nil, name: "DataProtocol")

          case .foundationURL where !config.effectiveFoundationTypesAsJavaTypes,
            .essentialsURL where !config.effectiveFoundationTypesAsJavaTypes:
            return .class(package: nil, name: "URL")

          case .foundationUUID, .essentialsUUID:
            return .javaUtilUUID

          default:
            guard let javaType = JNIJavaTypeTranslator.translate(knownType: knownType.kind, config: self.config) else {
              throw JavaTranslationError.unsupportedSwiftType(swiftType)
            }
            return javaType.boxedType
          }
        }

        if nominalType.isSwiftJavaWrapper {
          guard let javaType = nominalTypeName.parseJavaClassFromSwiftJavaName(in: self.javaClassLookupTable) else {
            throw JavaTranslationError.wrappedJavaClassTranslationNotProvided(swiftType)
          }
          return javaType
        }

        // We assume this is a JExtract class.
        let typeParameters =
          try nominalType.genericArguments.map { swiftType in
            try translateGenericTypeParameter(
              swiftType,
              genericParameters: genericParameters,
              genericRequirements: genericRequirements,
            )
          }

        return .class(
          package: moduleJavaPackages[nominalType.nominalTypeDecl.moduleName],
          name: nominalTypeName,
          typeParameters: typeParameters,
        )

      case .genericParameter(let generic):
        if let concreteTy = swiftType.typeIn(
          genericParameters: genericParameters,
          genericRequirements: genericRequirements,
        ) {
          return try translateGenericTypeParameter(
            concreteTy,
            genericParameters: genericParameters,
            genericRequirements: genericRequirements,
          )
        }
        return .class(package: nil, name: generic.name)

      case .tuple(let elements) where elements.count == 1:
        return try translateGenericTypeParameter(
          elements[0].type,
          genericParameters: genericParameters,
          genericRequirements: genericRequirements
        )

      case .tuple(let elements):
        let elementJavaTypes = try elements.map { element in
          try translateGenericTypeParameter(
            element.type,
            genericParameters: genericParameters,
            genericRequirements: genericRequirements
          )
        }
        return .tuple(elementTypes: elementJavaTypes)

      case .metatype, .function, .existential, .opaque, .composite, .inlineArray:
        throw JavaTranslationError.unsupportedSwiftType(swiftType)
      }
    }

    /// - Parameter: methodName is necessary because we may need to form an ad-hoc one off type if e.g. named tuples are used.
    func translateTupleResult(
      methodName: String,
      elements: [SwiftTupleElement],
      resultName: String = "result",
      genericParameters: [SwiftGenericParameterDeclaration],
      genericRequirements: [SwiftGenericRequirement],
    ) throws -> TranslatedResult {
      var outParameters: [OutParameter] = []
      var elementOutParamNames: [String] = []
      var elementConversions: [JavaNativeConversionStep] = []
      var elementJavaTypes: [JavaType] = []

      for (idx, element) in elements.enumerated() {
        let outParamName = "\(resultName)_\(idx)$"

        // Determine the Java type for this element
        let elementResult = try translateResult(
          swiftType: element.type,
          methodName: methodName,
          resultName: outParamName,
          genericParameters: genericParameters,
          genericRequirements: genericRequirements,
        )

        // out names are always ...$N, no need to use real named tuple names here, this is just for the thunk
        elementOutParamNames.append(outParamName)
        outParameters.append(contentsOf: elementResult.outParameters)

        if !elementResult.nativeJavaType.isVoid {
          let arrayType: JavaType = .array(elementResult.nativeJavaType)
          outParameters.append(
            OutParameter(name: outParamName, type: arrayType, allocation: .newArray(elementResult.nativeJavaType, size: 1))
          )
          elementConversions.append(elementResult.conversion)
        } else {
          elementConversions.append(.placeToVar(elementResult.conversion, name: "\(resultName)_\(idx)"))
        }
        elementJavaTypes.append(elementResult.javaType)
      }

      let isNamedTuple = elements.contains { $0.label != nil }
      let names = elements.enumerated().map { idx, element in
        if let label = element.label {
          label
        } else {
          "$\(idx)"
        }
      }

      let tupleElements: [(outParamName: String, elementConversion: JavaNativeConversionStep)] =
        zip(elementOutParamNames, elementConversions).map { ($0, $1) }

      let javaResultType: JavaType =
        if isNamedTuple {
          .labeledTuple(methodName, names: names, elementTypes: elementJavaTypes)
        } else {
          .tuple(elementTypes: elementJavaTypes)
        }

      let javaNativeConversionStep: JavaNativeConversionStep =
        .tupleFromOutParams(
          tupleClassName: "\(javaResultType)",
          elements: tupleElements
        )

      // Collect annotations from tuple elements - if any element is @Unsigned,
      // propagate that to the method level
      var tupleAnnotations: [JavaAnnotation] = []
      for element in elements {
        let elementAnnotations = getJavaTypeAnnotations(swiftType: element.type, config: config)
        for annotation in elementAnnotations where !tupleAnnotations.contains(annotation) {
          tupleAnnotations.append(annotation)
        }
      }

      return TranslatedResult(
        javaType: javaResultType,
        nativeJavaType: .void,
        annotations: tupleAnnotations,
        outParameters: outParameters,
        conversion: javaNativeConversionStep
      )
    }

    func translateOptionalResult(
      wrappedType swiftType: SwiftType,
      methodName: String,
      resultName: String,
      genericParameters: [SwiftGenericParameterDeclaration],
      genericRequirements: [SwiftGenericRequirement],
    ) throws -> TranslatedResult {
      let discriminatorName = "\(resultName)$_discriminator$"

      let parameterAnnotations: [JavaAnnotation] = getJavaTypeAnnotations(swiftType: swiftType, config: config)

      switch swiftType {
      case .nominal(let nominalType):
        let nominalTypeName = nominalType.nominalTypeDecl.qualifiedName
        if let knownType = nominalType.nominalTypeDecl.knownTypeKind {
          if let javaType = JNIJavaTypeTranslator.translate(knownType: knownType, config: self.config),
            javaType.implementsJavaValue
          {
            guard let returnType = javaType.optionalType, let optionalClass = javaType.optionalWrapperType else {
              break
            }

            // Check if we can fit the value and a discriminator byte in a primitive.
            // so the return JNI value will be (value, discriminator)
            if let nextIntergralTypeWithSpaceForByte = javaType.nextIntergralTypeWithSpaceForByte {
              return TranslatedResult(
                javaType: .class(package: nil, name: returnType),
                nativeJavaType: nextIntergralTypeWithSpaceForByte.javaType,
                annotations: parameterAnnotations,
                outParameters: [],
                conversion: .combinedValueToOptional(
                  .placeholder,
                  nextIntergralTypeWithSpaceForByte.javaType,
                  resultName: resultName,
                  valueType: javaType,
                  valueSizeInBytes: nextIntergralTypeWithSpaceForByte.valueBytes,
                  optionalType: optionalClass,
                ),
              )
            } else {
              // Otherwise, we return the result as normal, but
              // use an indirect return for the discriminator.
              return TranslatedResult(
                javaType: .class(package: nil, name: returnType),
                nativeJavaType: javaType,
                annotations: parameterAnnotations,
                outParameters: [
                  OutParameter(name: discriminatorName, type: .array(.byte), allocation: .newArray(.byte, size: 1))
                ],
                conversion: .toOptionalFromIndirectReturn(
                  discriminatorName: .constant(discriminatorName),
                  optionalClass: optionalClass,
                  nativeResultJavaType: javaType,
                  toValue: .placeholder,
                  resultName: resultName,
                ),
              )
            }
          }
        }

        if nominalType.isSwiftJavaWrapper {
          guard let javaType = nominalTypeName.parseJavaClassFromSwiftJavaName(in: self.javaClassLookupTable) else {
            throw JavaTranslationError.wrappedJavaClassTranslationNotProvided(swiftType)
          }
          return TranslatedResult(
            javaType: javaType,
            nativeJavaType: javaType,
            annotations: parameterAnnotations,
            outParameters: [],
            conversion: .placeholder
          )
        }

      case .tuple:
        break

      default:
        throw JavaTranslationError.unsupportedSwiftType(swiftType)
      }

      // Common indirect conversion
      var javaType = try translateGenericTypeParameter(
        swiftType,
        genericParameters: genericParameters,
        genericRequirements: genericRequirements,
      )

      let wrappedValueResult = try translateResult(
        swiftType: swiftType,
        methodName: methodName,
        resultName: resultName + "Wrapped$",
        genericParameters: genericParameters,
        genericRequirements: genericRequirements,
      )

      // The optional wraps the value itself: an array of primitives is the `long[]` the native method
      // returned, not `java.lang.Long[]`, and a labeled tuple is its generated `LabeledTuple_…` class,
      // which is printed because the result type names it.
      if case .array(let element) = wrappedValueResult.javaType, element.isPrimitive {
        javaType = wrappedValueResult.javaType
      } else if wrappedValueResult.javaType.isSwiftJavaLabeledTuple {
        javaType = wrappedValueResult.javaType
      }

      let returnType = JavaType.optional(javaType)
      return TranslatedResult(
        javaType: returnType,
        nativeJavaType: wrappedValueResult.nativeJavaType,
        annotations: parameterAnnotations,
        outParameters: [
          OutParameter(name: discriminatorName, type: .array(.byte), allocation: .newArray(.byte, size: 1))
        ] + wrappedValueResult.outParameters,
        conversion: .toOptionalFromIndirectReturn(
          discriminatorName: .constant(discriminatorName),
          optionalClass: "Optional",
          nativeResultJavaType: wrappedValueResult.nativeJavaType,
          toValue: wrappedValueResult.conversion,
          resultName: resultName
        )
      )
    }

    func translateArrayParameter(
      elementType: SwiftType,
      parameterName: String,
      genericParameters: [SwiftGenericParameterDeclaration],
      genericRequirements: [SwiftGenericRequirement],
    ) throws -> TranslatedParameter {
      let parameterAnnotations: [JavaAnnotation] = getJavaTypeAnnotations(swiftType: elementType, config: config)

      switch elementType {
      case .nominal(let nominalType) where nominalType.nominalTypeDecl.knownTypeKind == .array:
        guard let fullKnownType = nominalType.asKnownType else {
          throw JavaTranslationError.unsupportedSwiftType(elementType)
        }

        guard case .array(let innerElement) = fullKnownType else {
          throw JavaTranslationError.unsupportedSwiftType(elementType)
        }

        let innerParam = try translateArrayParameter(
          elementType: innerElement,
          parameterName: parameterName,
          genericParameters: genericParameters,
          genericRequirements: genericRequirements
        )
        let innerJavaType = innerParam.parameter.type.javaType
        let nonNull = JavaNativeConversionStep.requireNonNull(.placeholder, message: "\(parameterName) must not be null")
        if case .requireNonNull(.placeholder, _) = innerParam.conversion {
          return TranslatedParameter(
            parameter: JavaParameter(name: parameterName, type: .array(innerJavaType), annotations: parameterAnnotations),
            conversion: nonNull
          )
        }
        // Rows of jextracted values: convert each row to its pointers, like a one-dimensional array.
        return TranslatedParameter(
          parameter: JavaParameter(name: parameterName, type: .array(innerJavaType), annotations: parameterAnnotations),
          conversion: .method(
            .method(
              .arraysStream(nonNull),
              function: "map",
              arguments: [.lambda(args: ["row"], body: .replacingPlaceholder(innerParam.conversion, placeholder: "row"))]
            ),
            function: "toArray",
            arguments: [.constant("\(innerJavaType.replacingArrayElement(with: .long))[]::new")]
          )
        )

      case .nominal(let nominalType) where nominalType.isBridgedArrayElement:
        let javaType = try bridgedArrayElementJavaType(
          elementType,
          genericParameters: genericParameters,
          genericRequirements: genericRequirements
        )
        return TranslatedParameter(
          parameter: JavaParameter(name: parameterName, type: .array(javaType), annotations: parameterAnnotations),
          conversion: .requireNonNull(.placeholder, message: "\(parameterName) must not be null")
        )

      case .nominal(let nominalType):
        if let knownType = nominalType.nominalTypeDecl.knownTypeKind {
          guard let javaType = JNIJavaTypeTranslator.translate(knownType: knownType, config: self.config) else {
            throw JavaTranslationError.unsupportedSwiftType(elementType)
          }

          return TranslatedParameter(
            parameter: JavaParameter(name: parameterName, type: .array(javaType), annotations: parameterAnnotations),
            conversion: .requireNonNull(.placeholder, message: "\(parameterName) must not be null"),
          )
        }

        guard !nominalType.isSwiftJavaWrapper else {
          throw JavaTranslationError.unsupportedSwiftType(elementType)
        }

        let javaType = try translateGenericTypeParameter(
          elementType,
          genericParameters: genericParameters,
          genericRequirements: genericRequirements,
        )
        // Assume JExtract imported class
        return TranslatedParameter(
          parameter: JavaParameter(
            name: parameterName,
            type: .array(javaType),
            annotations: parameterAnnotations,
          ),
          conversion: .method(
            .method(
              .arraysStream(.requireNonNull(.placeholder, message: "\(parameterName) must not be null")),
              function: "mapToLong",
              arguments: [.constant("\(javaType)::$memoryAddress")],
            ),
            function: "toArray",
            arguments: [],
          ),
        )

      default:
        throw JavaTranslationError.unsupportedSwiftType(elementType)
      }
    }

    func translateArrayResult(
      elementType: SwiftType,
      genericParameters: [SwiftGenericParameterDeclaration],
      genericRequirements: [SwiftGenericRequirement],
    ) throws -> TranslatedResult {
      let annotations: [JavaAnnotation] = getJavaTypeAnnotations(swiftType: elementType, config: config)

      switch elementType {
      case .nominal(let nominalType) where nominalType.nominalTypeDecl.knownTypeKind == .array:
        guard let fullKnownType = nominalType.asKnownType else {
          throw JavaTranslationError.unsupportedSwiftType(elementType)
        }

        guard case .array(let innerElement) = fullKnownType else {
          throw JavaTranslationError.unsupportedSwiftType(elementType)
        }

        let innerResult = try translateArrayResult(
          elementType: innerElement,
          genericParameters: genericParameters,
          genericRequirements: genericRequirements
        )
        if case .placeholder = innerResult.conversion {
          return TranslatedResult(
            javaType: .array(innerResult.javaType),
            nativeJavaType: .array(innerResult.javaType),
            annotations: annotations,
            outParameters: [],
            conversion: .placeholder
          )
        }
        // Rows of jextracted values: wrap each row's pointers, like a one-dimensional array.
        return TranslatedResult(
          javaType: .array(innerResult.javaType),
          nativeJavaType: .array(innerResult.nativeJavaType),
          annotations: annotations,
          outParameters: [],
          conversion: .method(
            .method(
              .arraysStream(.placeholder),
              function: "map",
              arguments: [.lambda(args: ["row"], body: .replacingPlaceholder(innerResult.conversion, placeholder: "row"))]
            ),
            function: "toArray",
            arguments: [.constant("\(innerResult.javaType)[]::new")]
          )
        )

      case .nominal(let nominalType) where nominalType.isBridgedArrayElement:
        let javaType = try bridgedArrayElementJavaType(
          elementType,
          genericParameters: genericParameters,
          genericRequirements: genericRequirements
        )
        // The native method returns the array `ArrayBridge` created, whose static type is `Object[]`.
        return TranslatedResult(
          javaType: .array(javaType),
          nativeJavaType: .array(.javaLangObject),
          annotations: annotations,
          outParameters: [],
          conversion: .cast(.placeholder, .array(javaType))
        )

      case .nominal(let nominalType):
        let nominalTypeName = nominalType.nominalTypeDecl.qualifiedName
        if let knownType = nominalType.nominalTypeDecl.knownTypeKind {
          guard let javaType = JNIJavaTypeTranslator.translate(knownType: knownType, config: self.config) else {
            throw JavaTranslationError.unsupportedSwiftType(elementType)
          }

          return TranslatedResult(
            javaType: .array(javaType),
            nativeJavaType: .array(javaType),
            annotations: annotations,
            outParameters: [],
            conversion: .placeholder,
          )
        }

        if nominalType.isSwiftJavaWrapper {
          guard let javaType = nominalTypeName.parseJavaClassFromSwiftJavaName(in: self.javaClassLookupTable) else {
            throw JavaTranslationError.wrappedJavaClassTranslationNotProvided(elementType)
          }

          return TranslatedResult(
            javaType: .array(javaType),
            nativeJavaType: .array(javaType),
            annotations: annotations,
            outParameters: [],
            conversion: .placeholder
          )
        }

        let javaType = try translateGenericTypeParameter(
          elementType,
          genericParameters: genericParameters,
          genericRequirements: genericRequirements,
        )
        // We assume this is a JExtract class.
        return TranslatedResult(
          javaType: .array(javaType),
          nativeJavaType: .array(.long),
          annotations: annotations,
          outParameters: [],
          conversion: .method(
            .method(
              .arraysStream(.placeholder),
              function: "mapToObj",
              arguments: [
                .lambda(
                  args: ["pointer"],
                  body: .wrapMemoryAddressUnsafe(.constant("pointer"), javaType),
                )
              ],
            ),
            function: "toArray",
            arguments: [.constant("\(javaType.fullyQualifiedClassName!)[]::new")]
          )
        )

      default:
        throw JavaTranslationError.unsupportedSwiftType(elementType)
      }
    }

    /// The Java type of an element converted by `ArrayBridge`. Its `OptionalBridge` always creates a
    /// `java.util.Optional`, also for primitives (`Optional<Long>`, not `OptionalLong`).
    func bridgedArrayElementJavaType(
      _ swiftType: SwiftType,
      genericParameters: [SwiftGenericParameterDeclaration],
      genericRequirements: [SwiftGenericRequirement],
    ) throws -> JavaType {
      if case .nominal(let nominalType) = swiftType, case .optional(let wrapped) = nominalType.asKnownType {
        let wrappedJavaType = try bridgedArrayElementJavaType(
          wrapped,
          genericParameters: genericParameters,
          genericRequirements: genericRequirements
        )
        return .optional(wrappedJavaType.boxedType)
      }
      return try translateGenericTypeParameter(
        swiftType,
        genericParameters: genericParameters,
        genericRequirements: genericRequirements,
      )
    }

    func javaTypeForDictionaryComponent(
      _ swiftType: SwiftType,
      genericParameters: [SwiftGenericParameterDeclaration],
      genericRequirements: [SwiftGenericRequirement],
    ) throws -> JavaType {
      switch swiftType {
      case let .tuple(elements):
        if elements.count != 1 { throw JavaTranslationError.unsupportedSwiftType(swiftType) }
      default:
        break
      }

      return try translateGenericTypeParameter(
        swiftType,
        genericParameters: genericParameters,
        genericRequirements: genericRequirements,
      )
    }

    func translateDictionaryParameter(
      keyType: SwiftType,
      valueType: SwiftType,
      parameterName: String,
      genericParameters: [SwiftGenericParameterDeclaration],
      genericRequirements: [SwiftGenericRequirement],
    ) throws -> TranslatedParameter {
      let keyJavaType = try javaTypeForDictionaryComponent(
        keyType,
        genericParameters: genericParameters,
        genericRequirements: genericRequirements,
      )
      let valueJavaType = try javaTypeForDictionaryComponent(
        valueType,
        genericParameters: genericParameters,
        genericRequirements: genericRequirements,
      )
      let dictType = JavaType.swiftDictionaryMap(keyJavaType, valueJavaType)

      return TranslatedParameter(
        parameter: JavaParameter(name: parameterName, type: dictType),
        conversion: .method(
          .requireNonNull(.placeholder, message: "\(parameterName) must not be null"),
          function: "$memoryAddress",
          arguments: [],
        ),
      )
    }

    func translateDictionaryResult(
      keyType: SwiftType,
      valueType: SwiftType,
      genericParameters: [SwiftGenericParameterDeclaration],
      genericRequirements: [SwiftGenericRequirement],
    ) throws -> TranslatedResult {
      let keyJavaType = try javaTypeForDictionaryComponent(
        keyType,
        genericParameters: genericParameters,
        genericRequirements: genericRequirements,
      )
      let valueJavaType = try javaTypeForDictionaryComponent(
        valueType,
        genericParameters: genericParameters,
        genericRequirements: genericRequirements,
      )
      let dictType = JavaType.swiftDictionaryMap(keyJavaType, valueJavaType)

      return TranslatedResult(
        javaType: dictType,
        nativeJavaType: .long,
        outParameters: [],
        conversion: .wrapMemoryAddressUnsafe(.placeholder, dictType),
      )
    }

    func translateSetParameter(
      elementType: SwiftType,
      parameterName: String,
      genericParameters: [SwiftGenericParameterDeclaration],
      genericRequirements: [SwiftGenericRequirement],
    ) throws -> TranslatedParameter {
      let elementJavaType = try javaTypeForDictionaryComponent(
        elementType,
        genericParameters: genericParameters,
        genericRequirements: genericRequirements,
      )
      let setType = JavaType.swiftSet(elementJavaType)

      return TranslatedParameter(
        parameter: JavaParameter(name: parameterName, type: setType),
        conversion: .method(
          .requireNonNull(.placeholder, message: "\(parameterName) must not be null"),
          function: "$memoryAddress",
          arguments: [],
        ),
      )
    }

    func translateSetResult(
      elementType: SwiftType,
      genericParameters: [SwiftGenericParameterDeclaration],
      genericRequirements: [SwiftGenericRequirement],
    ) throws -> TranslatedResult {
      let elementJavaType = try javaTypeForDictionaryComponent(
        elementType,
        genericParameters: genericParameters,
        genericRequirements: genericRequirements,
      )
      let setType = JavaType.swiftSet(elementJavaType)

      return TranslatedResult(
        javaType: setType,
        nativeJavaType: .long,
        outParameters: [],
        conversion: .wrapMemoryAddressUnsafe(.placeholder, setType),
      )
    }
  }

  struct TranslatedEnumCase {
    /// The corresponding Java case class (CamelCased)
    let name: String

    /// The oringinal enum case.
    let original: ExtractedEnumCase

    /// A list of the translated associated values
    let parameters: [JavaParameter]

    let getAsCaseFunction: ExtractedFunc?

    /// Returns whether the associated values require an arena
    let requiresSwiftArena: Bool
  }

  struct TranslatedFunctionDecl {
    /// Java function name
    var name: String

    var isStatic: Bool

    var isThrowing: Bool

    /// The Java exception type for functions with typed throws of an extracted error type, `nil` otherwise.
    var thrownJavaType: JavaType?

    var isAsync: Bool

    var isIsolated: Bool

    var isImplicitlyAsync: Bool

    /// The name of the native function
    var nativeFunctionName: String

    /// The name of the Java parent scope this function is declared in
    var parentName: SwiftQualifiedTypeName

    /// The class holding `functionTypes`: the Java method name, or a getter's setter name.
    var closureHelperClassName: String

    /// Functional interfaces required for the Java method.
    var functionTypes: [TranslatedFunctionType]

    /// Function signature of the Java function the user will call
    var translatedFunctionSignature: TranslatedFunctionSignature

    /// Function signature of the native function that will be implemented by Swift
    var nativeFunctionSignature: NativeFunctionSignature

    /// Annotations to include on the Java function declaration
    var annotations: [JavaAnnotation] {
      self.translatedFunctionSignature.annotations
    }

    func throwsClause() -> String {
      let isSyncThrowing = !(isAsync || isIsolated || isImplicitlyAsync)
      let thrownException = (isSyncThrowing ? thrownJavaType?.fullyQualifiedClassName : nil) ?? "Exception"
      guard !translatedFunctionSignature.exceptions.isEmpty else {
        return isThrowing && isSyncThrowing ? " throws \(thrownException)" : ""
      }

      let signatureExceptions = translatedFunctionSignature.exceptions.compactMap(\.type.className).joined(
        separator: ", "
      )
      return " throws \(signatureExceptions)\(isThrowing ? ", \(thrownException)" : "")"
    }
  }

  struct TranslatedFunctionSignature {
    var selfParameter: TranslatedParameter?
    var selfTypeParameter: TranslatedParameter?
    var parameters: [TranslatedParameter]
    var result: TranslatedResult
    var exceptions: [JavaExceptionType]

    // if the result type implied any annotations,
    // propagate them onto the function the result is returned from
    var annotations: [JavaAnnotation] {
      self.result.annotations
    }

    var requiresSwiftArena: Bool {
      self.result.conversion.requiresSwiftArena
    }
  }

  /// Represent a Swift API parameter translated to Java.
  struct TranslatedParameter {
    let parameter: JavaParameter
    let conversion: JavaNativeConversionStep
  }

  /// Represent a Swift API result translated to Java.
  struct TranslatedResult {
    var javaType: JavaType

    /// result type of native function
    var nativeJavaType: JavaType

    /// Java annotations that should be propagated from the result type onto the method
    var annotations: [JavaAnnotation] = []

    var outParameters: [OutParameter]

    /// Represents how to convert the Java native result into a user-facing result.
    var conversion: JavaNativeConversionStep
  }

  struct OutParameter {
    enum Allocation {
      case newArray(JavaType, size: Int)
      case new

      func render(type: JavaType) -> String {
        switch self {
        case .newArray(let javaType, let size):
          // For array element types like byte[], we need "new byte[size][]"
          // not "new byte[][size]"
          var baseType = javaType
          var extraDimensions = ""
          while case .array(let inner) = baseType {
            extraDimensions += "[]"
            baseType = inner
          }
          return "new \(baseType)[\(size)]\(extraDimensions)"

        case .new:
          return "new \(type)()"
        }
      }
    }

    let name: String
    let type: JavaType
    let allocation: Allocation
  }

  /// Represent a Swift closure type in the user facing Java API.
  ///
  /// Closures are translated to named functional interfaces in Java.
  struct TranslatedFunctionType {
    var name: String
    var parameters: [TranslatedParameter]
    var result: TranslatedResult
    var swiftType: SwiftFunctionType

    var isEscaping: Bool { swiftType.isEscaping }

    /// Represents this `TranslatedFunctionType` if we need to create a synthetic protocol
    /// to handle the cross-language call to the function (closure).
    ///
    /// E.g. if the function type we're in is `@escaping` we need to create an
    /// interface on the Java side to represent it, and a Swift side wrapper to
    /// retain/wrap it, that will be then called into from the escaping Swift-side
    /// closure we forward to the downcall target.
    var syntheticClosureType: SyntheticEscapingClosureFunctionType?
  }

  /// Describes how to convert values between Java types and the native Java function
  enum JavaNativeConversionStep {
    /// The value being converted
    case placeholder

    case constant(String)

    /// `input_component`
    case combinedName(component: String)

    // Convert the results of the inner steps to a comma separated list.
    indirect case commaSeparated([JavaNativeConversionStep])

    /// `value.$memoryAddress()`
    indirect case valueMemoryAddress(JavaNativeConversionStep)

    /// `value.$typeMetadataAddress()`
    indirect case typeMetadataAddress(JavaNativeConversionStep)

    /// Call `new \(Type)(\(placeholder), swiftArena)`
    indirect case constructSwiftValue(JavaNativeConversionStep, JavaType)

    /// Call `new \(Type)(\(placeholder))`
    indirect case constructJavaClass(JavaNativeConversionStep, JavaType)

    /// Call the `MyType.wrapMemoryAddressUnsafe` in order to wrap a memory address using the Java binding type
    indirect case wrapMemoryAddressUnsafe(JavaNativeConversionStep, JavaType)

    indirect case call(JavaNativeConversionStep, function: String)

    indirect case method(JavaNativeConversionStep, function: String, arguments: [JavaNativeConversionStep] = [])

    indirect case member(JavaNativeConversionStep, field: String)

    case isOptionalPresent

    indirect case combinedValueToOptional(
      JavaNativeConversionStep,
      JavaType,
      resultName: String,
      valueType: JavaType,
      valueSizeInBytes: Int,
      optionalType: String,
    )

    indirect case ternary(
      JavaNativeConversionStep,
      thenExp: JavaNativeConversionStep,
      elseExp: JavaNativeConversionStep,
    )

    indirect case equals(JavaNativeConversionStep, JavaNativeConversionStep)

    indirect case subscriptOf(JavaNativeConversionStep, arguments: [JavaNativeConversionStep])

    static func toOptionalFromIndirectReturn(
      discriminatorName: JavaNativeConversionStep,
      optionalClass: String,
      nativeResultJavaType: JavaType,
      toValue valueConversion: JavaNativeConversionStep,
      resultName: String,
    ) -> JavaNativeConversionStep {
      .aggregate(
        variable: nativeResultJavaType.isVoid ? nil : (name: "\(resultName)$", type: nativeResultJavaType),
        [
          .ternary(
            .equals(
              .subscriptOf(discriminatorName, arguments: [.constant("0")]),
              .constant("1"),
            ),
            thenExp: .method(.constant(optionalClass), function: "of", arguments: [valueConversion]),
            elseExp: .method(.constant(optionalClass), function: "empty"),
          )
        ],
      )
    }

    /// Perform multiple conversions using the same input.
    case aggregate(variable: (name: String, type: JavaType)? = nil, [JavaNativeConversionStep])

    indirect case ifStatement(
      JavaNativeConversionStep,
      thenExp: JavaNativeConversionStep,
      elseExp: JavaNativeConversionStep? = nil,
    )

    /// Access a member of the value
    indirect case replacingPlaceholder(JavaNativeConversionStep, placeholder: String)

    /// `(args) -> { return body; }`
    indirect case lambda(args: [String] = [], body: JavaNativeConversionStep)

    /// Prints the conversion step, ignoring the output.
    indirect case print(JavaNativeConversionStep)

    indirect case requireNonNull(JavaNativeConversionStep, message: String)

    /// `(type) inner`
    indirect case cast(JavaNativeConversionStep, JavaType)

    /// Constructs a TupleN from out-parameter arrays.
    /// E.g. `new Tuple2<>(result_0$[0], result_1$[0])`
    case tupleFromOutParams(tupleClassName: String, elements: [(outParamName: String, elementConversion: JavaNativeConversionStep)])

    indirect case placeToVar(JavaNativeConversionStep, name: String, type: JavaType? = nil)

    /// A lambda of `interfaceType` over the Swift closure whose handle is the inner value; its arguments
    /// and result are boxed through `SwiftClosure.call`. Optional when the handle may be 0, for `nil`.
    indirect case swiftClosure(
      JavaNativeConversionStep,
      interfaceType: JavaType,
      parameters: [JavaType],
      result: JavaType,
      optional: OptionalForm?
    )

    enum OptionalForm {
      case nullable
      case javaOptional
    }

    /// `Arrays.stream(args)`
    static func arraysStream(_ argument: JavaNativeConversionStep) -> JavaNativeConversionStep {
      .method(.constant("Arrays"), function: "stream", arguments: [argument])
    }

    /// Returns the conversion string applied to the placeholder.
    func render(_ printer: inout JavaPrinter, _ placeholder: String) -> String {
      // NOTE: 'printer' is used if the conversion wants to cause side-effects.
      // E.g. storing a temporary values into a variable.
      switch self {
      case .placeholder:
        return placeholder

      case .constant(let value):
        return value

      case .combinedName(let component):
        return "\(placeholder)_\(component)"

      case .commaSeparated(let list):
        return list.map({ $0.render(&printer, placeholder) }).joined(separator: .comma)

      case .valueMemoryAddress:
        return "\(placeholder).$memoryAddress()"

      case .typeMetadataAddress(let inner):
        let inner = inner.render(&printer, placeholder)
        return "\(inner).$typeMetadataAddress()"

      case .constructSwiftValue(let inner, let javaType):
        let inner = inner.render(&printer, placeholder)
        return "new \(javaType)(\(inner), swiftArena)"

      case .wrapMemoryAddressUnsafe(let inner, let javaType):
        let inner = inner.render(&printer, placeholder)
        guard case .class(_, _, let typeParameters) = javaType else {
          fatalError("\(javaType) is not class.")
        }
        let genericClause =
          if !typeParameters.isEmpty {
            "<\(typeParameters.map(\.description).joined(separator: .comma))>"
          } else {
            ""
          }
        return "\(javaType.fullyQualifiedClassName!).\(genericClause)wrapMemoryAddressUnsafe(\(inner), swiftArena)"

      case .constructJavaClass(let inner, let javaType):
        let inner = inner.render(&printer, placeholder)
        return "new \(javaType)(\(inner))"

      case .call(let inner, let function):
        let inner = inner.render(&printer, placeholder)
        return "\(function)(\(inner))"

      case .isOptionalPresent:
        return "(byte) (\(placeholder).isPresent() ? 1 : 0)"

      case .method(let inner, let methodName, let arguments):
        let inner = inner.render(&printer, placeholder)
        let args = arguments.map { $0.render(&printer, placeholder) }
        let argsStr = args.joined(separator: .comma)
        return "\(inner).\(methodName)(\(argsStr))"

      case .member(let inner, let fieldName):
        let inner = inner.render(&printer, placeholder)
        return "\(inner).\(fieldName)"

      case .combinedValueToOptional(
        let combined,
        let combinedType,
        let resultName,
        let valueType,
        let valueSizeInBytes,
        let optionalType,
      ):
        let combined = combined.render(&printer, placeholder)
        printer.print(
          """
          \(combinedType) \(resultName)_combined$ = \(combined);
          byte \(resultName)_discriminator$ = (byte) (\(resultName)_combined$ & 0xFF);
          """
        )

        if valueType == .boolean {
          printer.print("boolean \(resultName)_value$ = ((byte) (\(resultName)_combined$ >> 8)) != 0;")
        } else {
          printer.print(
            "\(valueType) \(resultName)_value$ = (\(valueType)) (\(resultName)_combined$ >> \(valueSizeInBytes * 8));"
          )
        }

        return "\(resultName)_discriminator$ == 1 ? \(optionalType).of(\(resultName)_value$) : \(optionalType).empty()"

      case .ternary(let cond, let thenExp, let elseExp):
        let cond = cond.render(&printer, placeholder)
        let thenExp = thenExp.render(&printer, placeholder)
        let elseExp = elseExp.render(&printer, placeholder)
        return "(\(cond)) ? \(thenExp) : \(elseExp)"

      case .equals(let lhs, let rhs):
        let lhs = lhs.render(&printer, placeholder)
        let rhs = rhs.render(&printer, placeholder)
        return "\(lhs) == \(rhs)"

      case .subscriptOf(let inner, let arguments):
        let inner = inner.render(&printer, placeholder)
        let arguments = arguments.map { $0.render(&printer, placeholder) }
        return "\(inner)[\(arguments.joined(separator: .comma))]"

      case .aggregate(let variable, let steps):
        precondition(!steps.isEmpty, "Aggregate must contain steps")
        let toExplode: String
        if let variable {
          printer.print("\(variable.type) \(variable.name) = \(placeholder);")
          toExplode = variable.name
        } else {
          toExplode = placeholder
        }
        let steps = steps.map {
          $0.render(&printer, toExplode)
        }
        return steps.last!

      case .ifStatement(let cond, let thenExp, let elseExp):
        let cond = cond.render(&printer, placeholder)
        printer.printIfBlock("\(cond)") { printer in
          printer.print(thenExp.render(&printer, placeholder))
        }
        if let elseExp {
          printer.printBraceBlock("else") { printer in
            printer.print(elseExp.render(&printer, placeholder))
          }
        }

        return ""

      case .replacingPlaceholder(let inner, let placeholder):
        return inner.render(&printer, placeholder)

      case .lambda(let args, let body):
        var printer = JavaPrinter()
        printer.printBraceBlock("(\(args.joined(separator: .comma))) ->") { printer in
          let body = body.render(&printer, placeholder)
          if !body.isEmpty {
            printer.print("return \(body);")
          } else {
            printer.print("return;")
          }
        }
        return printer.finalize()

      case .print(let inner):
        let inner = inner.render(&printer, placeholder)
        printer.print("\(inner);")
        return ""

      case .requireNonNull(let inner, let message):
        let inner = inner.render(&printer, placeholder)
        return #"Objects.requireNonNull(\#(inner), "\#(message)")"#

      case .cast(let inner, let type):
        return "(\(type)) \(inner.render(&printer, placeholder))"

      case .tupleFromOutParams(let tupleClassName, let elements):
        var args: [String] = []
        for element in elements {
          let converted = element.elementConversion.render(&printer, "\(element.outParamName)[0]")
          args.append(converted)
        }
        return "new \(tupleClassName)(\(args.joined(separator: .comma)))"

      case .placeToVar(let inner, let name, let type):
        let inner = inner.render(&printer, placeholder)
        let type = type?.description ?? "var"
        printer.print("\(type) \(name) = \(inner);")
        return name

      case .swiftClosure(let inner, let interfaceType, let parameters, let result, let optional):
        let handle = inner.render(&printer, placeholder)
        let closureClass = "org.swift.swiftkit.core.SwiftClosure"
        if optional == nil {
          printer.print("\(closureClass) closure$ = new \(closureClass)(\(handle));")
        } else {
          printer.print("long closure$handle = \(handle);")
          printer.print("\(closureClass) closure$ = closure$handle == 0 ? null : new \(closureClass)(closure$handle);")
        }
        let names = parameters.indices.map { "closure$\($0)" }
        let lambdaParameters = zip(parameters, names).map { "\($0) \($1)" }.joined(separator: .comma)
        let call = "closure$.call(\(names.joined(separator: .comma)))"
        let body = result == .void ? call : "(\(result)) \(call)"
        let lambda = "(\(interfaceType)) (\(lambdaParameters)) -> \(body)"
        switch optional {
        case nil:
          return lambda
        case .nullable:
          return "closure$ == null ? null : \(lambda)"
        case .javaOptional:
          return "java.util.Optional.ofNullable(closure$ == null ? null : \(lambda))"
        }
      }
    }

    /// Whether the conversion uses SwiftArena.
    var requiresSwiftArena: Bool {
      switch self {
      case .placeholder, .constant, .isOptionalPresent, .combinedName:
        return false

      case .constructSwiftValue, .wrapMemoryAddressUnsafe:
        return true

      case .constructJavaClass(let inner, _):
        return inner.requiresSwiftArena

      case .valueMemoryAddress(let inner):
        return inner.requiresSwiftArena

      case .typeMetadataAddress(let inner):
        return inner.requiresSwiftArena

      case .commaSeparated(let list):
        return list.contains(where: { $0.requiresSwiftArena })

      case .method(let inner, _, let args):
        return inner.requiresSwiftArena || args.contains(where: \.requiresSwiftArena)

      case .member(let inner, _):
        return inner.requiresSwiftArena

      case .combinedValueToOptional(let inner, _, _, _, _, _):
        return inner.requiresSwiftArena

      case .ternary(let cond, let thenExp, let elseExp):
        return cond.requiresSwiftArena || thenExp.requiresSwiftArena || elseExp.requiresSwiftArena

      case .equals(let lhs, let rhs):
        return lhs.requiresSwiftArena || rhs.requiresSwiftArena

      case .subscriptOf(let inner, _):
        return inner.requiresSwiftArena

      case .aggregate(_, let steps):
        return steps.contains(where: \.requiresSwiftArena)

      case .ifStatement(let cond, let thenExp, let elseExp):
        return cond.requiresSwiftArena || thenExp.requiresSwiftArena || (elseExp?.requiresSwiftArena ?? false)

      case .call(let inner, _):
        return inner.requiresSwiftArena

      case .replacingPlaceholder(let inner, _):
        return inner.requiresSwiftArena

      case .lambda(_, let body):
        return body.requiresSwiftArena

      case .print(let inner):
        return inner.requiresSwiftArena

      case .requireNonNull(let inner, _), .cast(let inner, _):
        return inner.requiresSwiftArena

      case .tupleFromOutParams(_, let elements):
        return elements.contains(where: { $0.elementConversion.requiresSwiftArena })

      case .placeToVar(let inner, _, _):
        return inner.requiresSwiftArena

      case .swiftClosure(let inner, _, _, _, _):
        return inner.requiresSwiftArena
      }
    }
  }

  enum JavaTranslationError: Error {
    case unsupportedSwiftType(SwiftType, fileID: String, line: Int)

    static func unsupportedSwiftType(
      _ type: SwiftType,
      _fileID: String = #fileID,
      _line: Int = #line,
    ) -> JavaTranslationError {
      .unsupportedSwiftType(type, fileID: _fileID, line: _line)
    }

    case unsupportedSwiftType(known: SwiftKnownType, fileID: String, line: Int)
    static func unsupportedSwiftType(
      known type: SwiftKnownType,
      _fileID: String = #fileID,
      _line: Int = #line,
    ) -> JavaTranslationError {
      .unsupportedSwiftType(known: type, fileID: _fileID, line: _line)
    }

    /// The user has not supplied a mapping from `SwiftType` to
    /// a java class.
    case wrappedJavaClassTranslationNotProvided(SwiftType)

    /// `inout` parameters have no Java equivalent yet.
    case inoutParametersNotSupported

    /// Java can implement `async` protocol requirements only in `completableFuture` async mode.
    case asyncRequirementNeedsCompletableFuture

    /// `AsyncStream` elements must convert to a single Java value.
    case asyncStreamElementNotSupported

    // FIXME: Remove once we support protocol variables
    case protocolVariablesNotSupported

    case protocolStaticRequirementsNotSupported

    /// We cannot generate interface wrappers for
    /// protocols that we unable to be jextracted.
    case protocolWasNotExtracted

    /// Returning `any P` / `some P` is only supported when `P` is a single
    /// jextracted protocol.
    case cannotReturnNonExtractedProtocol(SwiftType)

    /// Dictionary type requires exactly two generic type arguments (key and value).
    case dictionaryRequiresKeyAndValueTypes(SwiftType)

    /// Set type requires exactly one generic type argument (element).
    case setRequiresElementType(SwiftType)

    /// Empty tuples are not supported in lowering, they should be treated as Void
    case emptyTuple(file: String, line: Int)
    static func emptyTuple(
      _file: String = #fileID,
      _line: Int = #line
    ) -> JavaTranslationError {
      .emptyTuple(file: _file, line: _line)
    }
  }
}

extension JNISwift2JavaGenerator.TranslatedFunctionDecl {
  /// The parameters of the `native` Java method, in declaration order.
  var nativeParameters: [JavaParameter] {
    let nativeSignature = self.nativeFunctionSignature
    var parameters = nativeSignature.parameters.flatMap(\.parameters)
    if let selfParameter = nativeSignature.selfParameter?.parameters {
      parameters += selfParameter
    }
    if let selfTypeParameter = nativeSignature.selfTypeParameter?.parameters {
      parameters += selfTypeParameter
    }
    return parameters + nativeSignature.result.outParameters
  }
}

extension JavaType {
  /// This array type with its innermost element replaced: `Item[][]` with `long` is `long[][]`.
  fileprivate func replacingArrayElement(with element: JavaType) -> JavaType {
    if case .array(let inner) = self {
      return .array(inner.replacingArrayElement(with: element))
    }
    return element
  }
}

/// The type, and its Java package, that declares the functional interfaces of a method's closure
/// parameters.
struct ClosureInterfaceOwner {
  var javaPackage: String
  var typeName: SwiftQualifiedTypeName
}

extension String {
  /// Names the generated Java methods and Swift thunks use for their own parameters and locals
  /// (`environment`, `result$`, `swiftArena`…).
  private static let thunkReservedNames: Set<String> = [
    "environment", "thisClass", "result", "selfPointer", "selfTypePointer", "swiftArena",
  ]

  /// A Swift parameter's name as a Java and thunk parameter: a reserved one gets a `_` suffix.
  fileprivate var thunkSafeParameterName: String {
    Self.thunkReservedNames.contains(self) ? self + "_" : self
  }
}
