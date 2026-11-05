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

import CodePrinting
import SwiftExtract
import SwiftJavaJNICore

extension JNISwift2JavaGenerator {

  /// Emit `@JavaInterface` Swift wrappers for each `@escaping` closure
  /// parameter of the passed in function.
  ///
  /// The wrapper's purpose is to retain the Java side object and delegate the calls on it to
  /// the Java object "callback".
  /// Each wrapper has it's corresponding Java side printed by `printJavaBindingWrapperHelperClass`.
  func printEscapingClosureSwiftFunctionHelperClasses(
    _ printer: inout SwiftPrinter,
    _ translatedDecl: TranslatedFunctionDecl,
  ) {
    for ty in translatedDecl.functionTypes {
      guard let closureTy = ty.syntheticClosureType else {
        continue
      }
      // With wrap-java's bindings, wrap-java generates these classes for us.
      if !usesWrapJavaBindings {
        let fn = closureTy.functionType
        for type in fn.parameters.map(\.type) + [fn.resultType] {
          for nominal in jextractedNominals(in: type) {
            printMinimalJavaClassWrapper(&printer, nominal)
          }
        }
      }
      printEscapingClosureWrapJavaInterface(&printer, closureTy)
    }
  }

  /// Whether wrap-java, run by the build plugin, generates the Swift bindings of the Java classes and
  /// interfaces Swift calls; otherwise jextract prints just enough of them.
  var usesWrapJavaBindings: Bool {
    config.effectiveEnableJavaCallbacks && config.effectiveJavaCallbacksBindings == .wrapJava
  }

  /// Prints the `@JavaInterface` binding of a protocol's Java interface that `wrapper` calls Java
  /// implementations through: a method for each requirement it calls with `@JavaMethod`.
  func printJavaInterfaceBinding(_ printer: inout SwiftPrinter, _ wrapper: JavaInterfaceSwiftWrapper) {
    let protocolDecl = wrapper.importedType.swiftNominal
    guard let javaPackage = javaPackage(of: protocolDecl) else {
      return
    }
    var methods: [String] = []
    for function in wrapper.functions {
      // Every requirement's conversions use the Java classes of its jextracted types.
      let signature = function.originalFunctionSignature
      for type in signature.parameters.map(\.type) + [signature.result.type] {
        for nominal in jextractedNominals(in: type) {
          printMinimalJavaClassWrapper(&printer, nominal)
        }
      }
      // `async` requirements are called with `dynamicJavaMethodCall`.
      guard !signature.isAsync,
        let requirement = wrapper.importedType.methods.first(where: {
          $0.name == function.swiftFunctionName && $0.functionSignature == signature
        }),
        let translatedDecl = translatedDecl(for: requirement)
      else {
        continue
      }
      var parameters = signature.parameters.enumerated().map { idx, parameter in
        "_ p\(idx): \(wrapJavaTypeName(parameter.type, isResult: false))"
      }
      if translatedDecl.translatedFunctionSignature.requiresSwiftArena {
        parameters.append("_ swiftArena: JavaSwiftArena?")
      }
      let throwsClause = signature.isThrowing ? " throws" : ""
      let resultClause =
        signature.result.type.isVoid ? "" : " -> \(wrapJavaTypeName(signature.result.type, isResult: true))"
      methods.append(
        """
        @JavaMethod("\(translatedDecl.name)")
        public func \(function.swiftFunctionName)(\(parameters.joined(separator: .comma)))\(throwsClause)\(resultClause)
        """
      )
    }
    let binaryName = "\(javaPackage).\(protocolDecl.qualifiedName.replacingOccurrences(of: ".", with: "$"))"
    printer.printBraceBlock(
      """
      @JavaInterface("\(binaryName)")
      public struct \(protocolDecl.javaInterfaceName)
      """
    ) { printer in
      printer.print(methods.joined(separator: "\n\n"))
    }
    printer.println()
  }

  /// A nominal type this module jextracts, which crosses into Java as its generated Java class.
  private func jextractedNominal(_ type: SwiftType) -> SwiftNominalTypeDeclaration? {
    // Types of this module, or of a jextracted module it depends on (its Java package is known).
    guard case .nominal(let nominal) = type, nominal.asKnownType == nil,
      javaPackage(of: nominal.nominalTypeDecl) != nil
    else {
      return nil
    }
    return nominal.nominalTypeDecl
  }

  private func javaPackage(of decl: SwiftNominalTypeDeclaration) -> String? {
    decl.moduleName == swiftModuleName ? javaPackage : moduleJavaPackages[decl.moduleName]
  }

  /// The jextracted types a value of `type` crosses into Java as: the type itself, or the elements of an
  /// optional or an array of them.
  private func jextractedNominals(in type: SwiftType) -> [SwiftNominalTypeDeclaration] {
    if let nominal = jextractedNominal(type) {
      return [nominal]
    }
    guard case .nominal(let nominal) = type else {
      return []
    }
    switch nominal.asKnownType {
    case .optional(let wrapped), .array(let wrapped):
      return jextractedNominals(in: wrapped)
    default:
      return []
    }
  }

  private func optionalWrapped(_ type: SwiftType) -> SwiftType? {
    guard case .nominal(let nominal) = type, case .optional(let wrapped) = nominal.asKnownType else {
      return nil
    }
    return wrapped
  }

  /// The Swift spelling of a closure parameter or result in the `@JavaInterface` wrapper.
  /// Jextracted types are passed as their Java class, through its JavaKit wrapper.
  private func wrapJavaTypeName(_ type: SwiftType, isResult: Bool) -> String {
    if type.isSwiftError {
      return isResult ? "Throwable!" : "Throwable?"
    }
    if config.effectiveDictionariesAsJavaMaps, let wrapper = type.javaMapObjectWrapperName {
      return wrapper + (isResult ? "!" : "?")
    }
    if !isResult, optionalWrapped(type)?.isSwiftError == true {
      return "JavaOptional<Throwable>?"
    }
    // A Java object implementing a protocol, which Swift checks for a Swift instance or a Java implementation.
    // Its Java type is the protocol's interface, which the Java method's signature names.
    if isResult, case .existential(let protocolType) = type, let protocolDecl = protocolType.asNominalTypeDeclaration {
      return "\(protocolDecl.javaInterfaceName)!"
    }
    if let nominal = jextractedNominal(type) {
      return nominal.generatedJavaClassMacroName + (isResult ? "!" : "?")
    }
    // With `kotlinOutput` an optional crosses as a nullable Java object.
    if !isResult, config.effectiveKotlinOutput, let wrapped = optionalWrapped(type) {
      if let boxClass = wrapped.javaBoxClassName {
        return "\(boxClass)?"
      }
      if let nominal = jextractedNominal(wrapped) {
        return "\(nominal.generatedJavaClassMacroName)?"
      }
    }
    if !isResult, let nominal = optionalWrapped(type).flatMap(jextractedNominal) {
      return "JavaOptional<\(nominal.generatedJavaClassMacroName)>?"
    }
    // Optional strings and numbers cross as what `Optional.toJavaOptional()` makes of them.
    if !isResult, let wrapped = optionalWrapped(type), case .nominal(let nominal) = wrapped {
      switch nominal.nominalTypeDecl.knownTypeKind {
      case .string: return "JavaOptional<JavaString>?"
      case .double: return "JavaOptionalDouble?"
      case .int32: return "JavaOptionalInt?"
      case .int64: return "JavaOptionalLong?"
      default: break
      }
    }
    // Arrays of jextracted values cross as arrays of their Java objects.
    if case .nominal(let array) = type, case .array(let element) = array.asKnownType,
      let nominal = jextractedNominal(element)
    {
      return "[\(nominal.generatedJavaClassMacroName)?]"
    }
    // An optional array is returned in a Java `Optional`, which holds the array as an object.
    if isResult, let wrapped = optionalWrapped(type), case .nominal(let array) = wrapped,
      case .array(let element) = array.asKnownType, jextractedNominal(element) != nil
    {
      return "JavaOptional<JavaObject>!"
    }
    return type.description
  }

  /// Prints just enough of a JavaKit wrapper (`@JavaClass` + `wrapMemoryAddressUnsafe`) for the
  /// generated Java class of a jextracted type, so closures can hand Swift values to Java without
  /// running wrap-java. Parents of nested types are printed first; each type is printed once.
  private func printMinimalJavaClassWrapper(_ printer: inout SwiftPrinter, _ decl: SwiftNominalTypeDeclaration) {
    guard !printedMinimalJavaClassWrappers.contains(decl.qualifiedName) else {
      return
    }
    printedMinimalJavaClassWrappers.insert(decl.qualifiedName)

    var names: [String] = []
    var current: SwiftNominalTypeDeclaration? = decl
    while let c = current {
      names.insert(c.name, at: 0)
      current = c.parent
    }
    let binaryName = "\(javaPackage(of: decl)!).\(names.joined(separator: "$"))"
    let className = "Java\(decl.name)"

    var classDecl =
      """
      @JavaClass("\(binaryName)")
      open class \(className): JavaObject {}
      """
    if let parent = decl.parent {
      printMinimalJavaClassWrapper(&printer, parent)
      classDecl = "extension \(parent.generatedJavaClassMacroName) {\n\(classDecl)\n}"
    }
    printer.print(
      """
      \(classDecl)
      extension JavaClass<\(decl.generatedJavaClassMacroName)> {
        @JavaStaticMethod
        public func wrapMemoryAddressUnsafe(_ selfPointer: Int64) -> \(decl.generatedJavaClassMacroName)!
      }
      """
    )
    printer.println()
  }

  private func printEscapingClosureWrapJavaInterface(
    _ printer: inout SwiftPrinter,
    _ closureTy: SyntheticEscapingClosureFunctionType,
  ) {
    guard printedEscapingClosureWrappers.insert(closureTy.javaInterfaceName).inserted else {
      return
    }
    // The Swift closures it takes, which Java calls through interfaces nested in its own.
    for (idx, param) in closureTy.functionType.parameters.enumerated() {
      guard case .function = param.type else {
        continue
      }
      let name = (param.parameterName ?? "_\(idx)").javaSafeIdentifier
      printer.print(
        """
        @JavaInterface("\(closureTy.javaBinaryName)$\(name)")
        public struct \(closureTy.javaInterfaceName)_\(name) {}

        extension JavaClass<\(closureTy.javaInterfaceName)> {
          @JavaStaticMethod("$\(name)FromSwiftClosure")
          public func _\(name)FromSwiftClosure(_ handle: Int64) -> \(closureTy.javaInterfaceName)_\(name)!
        }

        """
      )
    }
    printer.printBraceBlock(
      """
      @JavaInterface("\(closureTy.javaBinaryName)")
      public struct \(closureTy.javaInterfaceName)
      """
    ) { p in
      let signature = self.renderEscapingClosureApplySignature(closureTy.functionType, interface: closureTy.javaInterfaceName)
      p.print(
        """
        @JavaMethod
        public func \(config.effectiveClosureMethodName)\(signature)
        """
      )
    }
    printer.println()
  }

  private func renderEscapingClosureApplySignature(_ type: SwiftFunctionType, interface: String) -> String {
    let params = type.parameters.enumerated().map { idx, param -> String in
      let name = (param.parameterName ?? "_\(idx)").javaSafeIdentifier
      if case .function = param.type {
        return "_ \(name): \(interface)_\(name)?"
      }
      return "_ \(name): \(wrapJavaTypeName(param.type, isResult: false))"
    }
    let paramList = "(\(params.joined(separator: .comma)))"

    // Java returns a `CompletableFuture` for an async closure, which the closure awaits.
    if type.isAsync {
      return "\(paramList) -> JavaCompletableFuture!"
    }
    if type.resultType.isVoid {
      return paramList
    } else {
      return "\(paramList) -> \(wrapJavaTypeName(type.resultType, isResult: true))"
    }
  }
}

extension SwiftType {
  /// The SwiftJava wrapper a dictionary, `Any` or `AnyHashable`, or an optional of one, crosses as with
  /// `dictionariesAsJavaMaps`.
  var javaMapObjectWrapperName: String? {
    guard case .nominal(let nominal) = self else {
      return nil
    }
    switch nominal.asKnownType {
    case .optional(let wrapped): return wrapped.javaMapObjectWrapperName
    case .dictionary: return "JavaMap<JavaObject, JavaObject>"
    case .any, .anyHashable: return "JavaObject"
    default: return nil
    }
  }
}
