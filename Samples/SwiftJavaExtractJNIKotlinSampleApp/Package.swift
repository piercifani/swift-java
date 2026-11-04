// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Swift 6 language mode, with the generated bindings used from Kotlin (src/test/kotlin).
// KotlinSampleModels is a separate module so types and protocols cross module boundaries.
let package = Package(
  name: "SwiftJavaExtractJNIKotlinSampleApp",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "KotlinSampleModels", type: .dynamic, targets: ["KotlinSampleModels"]),
    .library(name: "KotlinSampleLibrary", type: .dynamic, targets: ["KotlinSampleLibrary"]),
  ],
  dependencies: [
    .package(name: "swift-java", path: "../../")
  ],
  targets: [
    .target(
      name: "KotlinSampleModels",
      dependencies: [
        .product(name: "SwiftJava", package: "swift-java")
      ],
      exclude: [
        "swift-java.config"
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ],
      plugins: [
        .plugin(name: "JExtractSwiftPlugin", package: "swift-java")
      ]
    ),
    .target(
      name: "KotlinSampleLibrary",
      dependencies: [
        .product(name: "SwiftJava", package: "swift-java"),
        "KotlinSampleModels",
      ],
      exclude: [
        "swift-java.config"
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ],
      plugins: [
        .plugin(name: "JExtractSwiftPlugin", package: "swift-java")
      ]
    ),
  ]
)
