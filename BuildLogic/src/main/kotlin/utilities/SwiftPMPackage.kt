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

package utilities

import kotlinx.serialization.Serializable
import org.gradle.api.Project
import org.gradle.kotlin.dsl.support.serviceOf
import org.gradle.process.ExecOperations
import java.io.ByteArrayOutputStream

@Serializable
internal data class SwiftPMPackage(
    val targets: List<SwiftPMTarget>,
)

internal fun Project.swiftPMPackage(): SwiftPMPackage {
    val stdout = ByteArrayOutputStream()
    serviceOf<ExecOperations>().exec {
        workingDir(projectDir)
        commandLine("swift", "package", "describe", "--type", "json")
        environment(SWIFT_JAVA_BUILD, "1")
        standardOutput = stdout
    }
    return json.decodeFromString<SwiftPMPackage>(stdout.toString())
}

/**
 * Set for the Swift builds Gradle runs. A package shared with Apple platforms can add the SwiftJava
 * dependency and the JExtractSwiftPlugin only when it's set, as swiftlang/swift-java#694 describes.
 */
internal const val SWIFT_JAVA_BUILD = "SWIFT_JAVA_BUILD"
