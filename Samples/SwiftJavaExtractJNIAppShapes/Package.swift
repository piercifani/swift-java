// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// The code shapes of a production multi-module app, extracted for Kotlin (src/test/kotlin): Swift 6,
// modules depending on each other's types, public API that isn't exported, Combine and Observation,
// main-actor view models with callbacks. See README.md for the shapes each module holds.
//
// Every module uses `failOnSkippedDeclarations`: building this package checks that jextract handles
// all of it, and that the Java and Swift it generates compile. Shapes jextract doesn't handle yet are
// marked `@JavaExport(false)` with a `// Gap:` comment.

let jextractedModule: [Target.Dependency] = [
  .product(name: "SwiftJava", package: "swift-java"),
  .product(name: "SwiftJavaAnnotations", package: "swift-java"),
]

func module(_ name: String, dependencies: [Target.Dependency] = []) -> Target {
  .target(
    name: name,
    dependencies: jextractedModule + dependencies,
    exclude: ["swift-java.config"],
    swiftSettings: [.swiftLanguageMode(.v6)],
    plugins: [.plugin(name: "JExtractSwiftPlugin", package: "swift-java")]
  )
}

let package = Package(
  name: "SwiftJavaExtractJNIAppShapes",
  platforms: [
    .iOS(.v18),
    .macOS(.v15),
  ],
  products: [
    // One library with every module, as an app ships them: a library per module would link copies of
    // the modules it depends on, and Swift casts fail between the copies. Each module's
    // swift-java.config names it in `nativeLibraryName`.
    .library(
      name: "ShapesApp",
      type: .dynamic,
      targets: ["ShapesUtil", "ShapesModels", "ShapesClients", "ShapesDependencies", "ShapesViewModels"]
    )
  ],
  dependencies: [
    .package(name: "swift-java", path: "../../")
  ],
  targets: [
    module("ShapesUtil"),
    module("ShapesModels", dependencies: ["ShapesUtil"]),
    module("ShapesClients", dependencies: ["ShapesModels", "ShapesUtil"]),
    module("ShapesDependencies", dependencies: ["ShapesClients", "ShapesModels", "ShapesUtil"]),
    module("ShapesViewModels", dependencies: ["ShapesDependencies", "ShapesClients", "ShapesModels", "ShapesUtil"]),
  ]
)
