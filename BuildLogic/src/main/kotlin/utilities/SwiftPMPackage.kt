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

@Serializable
internal data class SwiftPMPackage(
    val targets: List<SwiftPMTarget>,
)

internal fun Project.swiftPMPackage(): SwiftPMPackage {
    // Through `providers.exec`: Gradle deprecates starting a process at configuration time otherwise.
    val output = providers.exec {
        workingDir(projectDir)
        commandLine("swift", "package", "describe", "--type", "json")
    }.standardOutput.asText.get()
    return json.decodeFromString<SwiftPMPackage>(output)
}