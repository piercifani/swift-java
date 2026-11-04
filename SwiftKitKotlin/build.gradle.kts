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

import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.swift.build.utils.resolveSwiftKitVersion

// Kotlin adapters for SwiftKitCore types (for example SwiftAsyncStream as a Flow), kept out of
// SwiftKitCore so that it stays a plain Java library without a kotlinx-coroutines dependency.
plugins {
    id("build-logic.java-common-conventions")
    kotlin("jvm") version "2.4.21"
    `maven-publish`
}

group = "org.swift.swiftkit"

version = resolveSwiftKitVersion()

base {
    archivesName = "swiftkit-kotlin"
}

publishing {
    publications {
        create<MavenPublication>("maven") {
            groupId = group as? String
            artifactId = "swiftkit-kotlin"
            from(components["java"])
        }
    }
}

// Consumable down to Java 11, like SwiftKitCore
tasks.withType<JavaCompile>().configureEach {
    options.release.set(11)
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_11)
        freeCompilerArgs.add("-Xjdk-release=11")
    }
}

dependencies {
    api(projects.swiftKitCore)
    api("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.11.0")
}
