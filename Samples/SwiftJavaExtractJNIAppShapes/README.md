# App shapes

The code shapes of a production multi-module Swift app whose Swift code also runs on Android, used from
Kotlin through jextract (JNI mode). The domain (a reading app) is made up; the shapes are the ones the
app needed: how its modules depend on each other, what it exports and what it keeps Swift-only, and how
its view models talk to the UI.

Building the package runs jextract on every module and compiles the generated Swift; `./gradlew test`
compiles the generated Java and runs the Kotlin tests in `src/test/kotlin`. Every module sets
`failOnSkippedDeclarations`, so the build fails when jextract skips anything it didn't before.

```bash
swift build --disable-experimental-prebuilts --disable-sandbox
./gradlew test   # from the repository root: ./gradlew :Samples:SwiftJavaExtractJNIAppShapes:test
```

macOS only: it uses Combine (an app on Android uses an implementation of the same API, such as
OpenCombine) and runs main-actor tests on the process's first thread (`-XstartOnFirstThread`).

## Modules

| Module | `exportMode` | Shapes |
|---|---|---|
| `ShapesUtil` | `all` | static helpers, constants inferred from literals, `@autoclosure` arguments, Java keywords as names, a method named like `Object.wait()`, platform-specific API |
| `ShapesModels` | `annotated` | Codable entities with Foundation values, raw-value enums, enums with payloads (one carrying an `Error`, one whose case shadows a payload type), nested arrays, sets, optional labeled tuples, overloads that differ only in pointer types, clashing accessor names, a default-argument overload that would be ambiguous, a parameter named `result`, a `@MainActor` callback typealias |
| `ShapesClients` | `annotated` | client protocols used as bare existentials, protocol extensions implementing requirements and adding methods, mocks that rely on them, a requirement taking a closure, an extension of another module's type, dictionaries and sets of another module's types, Combine state |
| `ShapesDependencies` | `all` | a container of clients typed as another module's protocols, `@autoclosure @escaping` configuration returning another module's enum, app state, async functions taking entities |
| `ShapesViewModels` | `annotated` | `@MainActor` and `@Observable` view models, callbacks typed with another module's `@MainActor` typealias, callbacks taking entities, arrays of entities, `[URL]`, optional strings and numbers, async callbacks returning futures |

All modules are linked into one library (`ShapesApp`, named by `nativeLibraryName` in each
`swift-java.config`), as an app ships them: with a library per module, each would link its own copy of
the modules it depends on, and Swift casts fail between the copies.

## Gaps

Shapes jextract doesn't handle yet are marked `@JavaExport(false)` with a `// Gap:` comment. Fixing one
means removing its annotation, which `failOnSkippedDeclarations` and the Kotlin tests then check.

- `#if`: without a static build configuration jextract treats every platform as active, so a macOS
  build gets thunks for `#if os(Android)` API (`Platform.androidOnly()`,
  `ShelfViewModel.androidBackPressed()`), and it treats `canImport(_:)` as false, so code inside
  `#if canImport(Combine)` isn't extracted.
- Generic classes used with type arguments (`StateValue<Int64>`).
- Closures returning a protocol type (`CatalogClient.makeSearch()`).
- Closures taking or returning optional arrays (`ShelfViewModel.setSeedProvider(_:)`).
- Optional arrays of primitives as parameters (`Shelf.withPageCounts(_:)`; they work as results).
- Enum cases with closure payloads over jextracted types (`SortPolicy`); a single case can't be left out
  either.
- An extension of another module's type (`extension Book` in `ShapesClients`) becomes a separate Java
  class, `com.example.shapes.clients.Book`, rather than members Kotlin can call on a
  `com.example.shapes.models.Book`.
