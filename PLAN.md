# Project Plan (keep this file up to date)

## Done
- Simplified the package to a single `Cassiopeia` library with no plugin/dylib baggage
- Implemented `RemoteCAS` + configuration for HTTP-backed CAS and action-cache operations
- Added remote-focused tests that exercise store/load/contains/action-cache flows via a mocked `URLProtocol`
- Documented the remote HTTP contract in `ARCHITECTURE.md`
- Verified `swift build` and `swift test` succeed after the refactor

## Next
- Exercise the client against a real CAS server endpoint to validate contract assumptions
- Evaluate authentication/header requirements (e.g. bearer tokens) and expose helpers if needed
- Author an OpenAPI YAML spec describing the HTTP contract and keep it at the repository root

## Blockers / Issues
- None at the moment

> Keep this plan current whenever tasks complete, new work starts, or blockers change.
