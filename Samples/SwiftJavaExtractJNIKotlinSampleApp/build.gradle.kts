//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift.org project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift.org project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import java.time.Duration
import utilities.javaLibraryPaths
import utilities.jextractGeneratedJavaDirs
import utilities.registerJextractTask

// The generated Java bindings, used from Kotlin: src/test/kotlin has one test file per feature.
plugins {
    id("build-logic.java-common-conventions")
    kotlin("jvm") version "2.4.21"
}

group = "org.swift.swiftkit"
version = "1.0-SNAPSHOT"

repositories {
    mavenCentral()
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of((gradle.extra.properties["swiftJavaJdk"] as? Int) ?: 17))
    }
}

val jextract = registerJextractTask {
    // FIXME: disable prebuilts until swift-syntax isn't broken on 6.2 anymore: https://github.com/swiftlang/swift-java/issues/418
    val cmdArgs = mutableListOf("build", "--disable-experimental-prebuilts", "--disable-sandbox")
    if (project.hasProperty("swiftSdk")) {
        cmdArgs.add("--swift-sdk")
        cmdArgs.add(project.property("swiftSdk").toString())
    }
    cmdArgs
}

sourceSets {
    main {
        java {
            srcDir(jextract)
            jextractGeneratedJavaDirs().forEach { srcDir(it) }
        }
    }
}

tasks.build {
    dependsOn(jextract)
}

dependencies {
    implementation(projects.swiftKitCore)
    implementation(projects.swiftKitKotlin)

    testImplementation(kotlin("test-junit5"))
    testRuntimeOnly(libs.junit.platform.launcher) // TODO: workaround for not finding junit: https://github.com/gradle/gradle/issues/34512
}

tasks.named<Test>("test") {
    useJUnitPlatform()
    // A deadlocked test fails instead of stalling the build.
    timeout.set(Duration.ofMinutes(2))

    jvmArgs(
        "--enable-native-access=ALL-UNNAMED",
        // Include the library paths where our dylibs are that we want to load and call
        "-Djava.library.path=" + javaLibraryPaths(project.projectDir).joinToString(File.pathSeparator),
    )

    // Run tests on the process's first thread, which Swift treats as the main actor's thread (as on
    // Android's UI thread), so main-actor isolated APIs can be called. macOS only.
    if (System.getProperty("os.name").startsWith("Mac")) {
        jvmArgs("-XstartOnFirstThread")
    }

    testLogging {
        events("failed")
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}
