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
      // With Java callbacks enabled, wrap-java generates these classes for us.
      if !config.effectiveEnableJavaCallbacks {
        let fn = closureTy.functionType
        for type in fn.parameters.map(\.type) + [fn.resultType] {
          if let nominal = jextractedNominal(type) ?? optionalWrapped(type).flatMap(jextractedNominal) {
            printMinimalJavaClassWrapper(&printer, nominal)
          }
        }
      }
      printEscapingClosureWrapJavaInterface(&printer, closureTy)
    }
  }

  /// A nominal type this module jextracts, which crosses into Java as its generated Java class.
  private func jextractedNominal(_ type: SwiftType) -> SwiftNominalTypeDeclaration? {
    guard case .nominal(let nominal) = type, nominal.asKnownType == nil,
      nominal.nominalTypeDecl.moduleName == swiftModuleName
    else {
      return nil
    }
    return nominal.nominalTypeDecl
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
    if let nominal = jextractedNominal(type) {
      return nominal.generatedJavaClassMacroName + (isResult ? "!" : "?")
    }
    if !isResult, let nominal = optionalWrapped(type).flatMap(jextractedNominal) {
      return "JavaOptional<\(nominal.generatedJavaClassMacroName)>?"
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
    let binaryName = "\(javaPackage).\(names.joined(separator: "$"))"
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
    printer.printBraceBlock(
      """
      @JavaInterface("\(closureTy.javaBinaryName)")
      public struct \(closureTy.javaInterfaceName)
      """
    ) { p in
      let signature = self.renderEscapingClosureApplySignature(closureTy.functionType)
      p.print(
        """
        @JavaMethod
        public func apply\(signature)
        """
      )
    }
    printer.println()
  }

  private func renderEscapingClosureApplySignature(_ type: SwiftFunctionType) -> String {
    let params = type.parameters.enumerated().map { idx, param -> String in
      let name = param.parameterName ?? "_\(idx)"
      return "_ \(name): \(wrapJavaTypeName(param.type, isResult: false))"
    }
    let paramList = "(\(params.joined(separator: .comma)))"

    if type.resultType.isVoid {
      return paramList
    } else {
      return "\(paramList) -> \(wrapJavaTypeName(type.resultType, isResult: true))"
    }
  }
}
