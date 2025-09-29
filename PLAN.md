# Project Plan (keep this file up to date)

## Done
- Simplified the package to a single `Cassiopeia` library with no plugin/dylib baggage
- Implemented `RemoteCAS` + configuration for HTTP-backed CAS and action-cache operations
- Added remote-focused tests that exercise store/load/contains/action-cache flows via a mocked `URLProtocol`
- Documented the remote HTTP contract in `ARCHITECTURE.md`
- Verified `swift build` and `swift test` succeed after the refactor

## In Progress
- Fixing Swift 6 compiler errors with optional unwrapping in the C bridge code
  - Added C header (CassiopeiaPluginAPI.h) and module map
  - Moved all bridge functions into Sources/Cassiopeia/PluginAPI.swift
  - Using `runAsyncAndWait` helper for sync functions (blocks thread, acceptable for C bridge)
  - Async callback variants properly implemented with Task{}
  - Compiler is having issues with optional unwrapping in closures (possible Swift 6 bug or edge case)

## Next
- Resolve compilation errors and complete swift build integration
- Exercise the client against a real CAS server endpoint to validate contract assumptions
- Evaluate authentication/header requirements (e.g. bearer tokens) and expose helpers if needed
- Author an OpenAPI YAML spec describing the HTTP contract and keep it at the repository root

## Blockers / Issues
- Swift 6 compiler treating unwrapped variables as still optional inside closures
- This might be related to the combination of: actor isolation, `@escaping` closures, and optional chaining

> Keep this plan current whenever tasks complete, new work starts, or blockers change.
