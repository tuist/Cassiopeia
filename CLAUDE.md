# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Build and Test
```bash
swift build                    # Build the package
swift test                     # Run all tests
```

### Swift 6 Specifics
- The project uses Swift 5.10+ with Swift 6 concurrency features
- Actor isolation checks are disabled via `-disable-actor-data-race-checks` flag
- Be aware of Swift 6 compiler edge cases around optional unwrapping in closures with actor isolation

## Architecture

### Overview
Cassiopeia is a **remote-first Content Addressable Storage (CAS) client** for swift-build that communicates over HTTP with a caching service. It implements `CASProtocol` and `ActionCacheProtocol` from swift-build's SWBUtil package.

### Core Components

**RemoteCAS Actor** (`Sources/Cassiopeia/RemoteCAS.swift`)
- The central implementation that bridges swift-build's protocols to HTTP
- All operations are async and use URLSession
- Encodes CASObject payloads as JSON with base64-encoded data
- Returns structured errors (RemoteCASError) for different failure modes

**Factory Methods** (`Sources/Cassiopeia/Cassiopeia.swift`)
- `Cassiopeia.makeRemoteCAS()` - Create with explicit baseURL and headers
- `Cassiopeia.makeRemoteCASFromEnvironment()` - Reads `COMPILATION_CACHE_REMOTE_SERVICE_PATH` from environment

**C Bridge API** (`Sources/Cassiopeia/PluginAPI.swift`)
- Implements the `llcas_*` C API that swift-build loads as a dynamic plugin
- Uses `@_cdecl` to export symbols matching the swift-build plugin contract
- Contains `runAsyncAndWait` helper to bridge async Swift to synchronous C functions (blocks calling thread)
- Maintains global RemoteCAS singleton via RemoteCASProvider actor
- ObjectStore actor manages loaded CASObject instances and assigns them opaque IDs for C interop

**Protocols** (`Sources/Cassiopeia/CASProtocol.swift`)
- `CASProtocol` - store, load, contains, delete operations
- `ActionCacheProtocol` - cache result mappings by action key
- These match the swift-build contract

### HTTP Contract
See `ARCHITECTURE.md` for the full HTTP contract specification. Key points:
- Base URL from `COMPILATION_CACHE_REMOTE_SERVICE_PATH`
- All paths relative to base: `/cas/objects/*` and `/cas/action-cache/*`
- Binary data is base64 encoded in JSON payloads
- DataID hashes are hex strings (SHA256)

**Endpoints:**
- `POST /cas/objects` - Store object, returns `{ "id": "<hash>" }`
- `GET /cas/objects/{hash}` - Load object, returns `{ "data": "<base64>", "refs": [...] }`
- `HEAD /cas/objects/{hash}` - Check existence (200 = exists, 404 = not found)
- `DELETE /cas/objects/{hash}` - Delete object
- `PUT /cas/action-cache/{key-hash}` - Store action cache mapping
- `GET /cas/action-cache/{key-hash}` - Lookup action cache mapping

### Package Structure
- **Cassiopeia target** - Main library built as dynamic library
- Dependencies: swift-crypto (SHA256), swift-build (SWBUtil for protocols)
- Platform: macOS 14.0+
- Tests: Mock URLProtocol simulates remote server responses

## Current Development Status

### Known Issues (from PLAN.md)
- Swift 6 compiler errors with optional unwrapping in the C bridge code
- Possible compiler bug around actor isolation + @escaping closures + optional chaining
- The C bridge uses nonisolated(unsafe) to work around some concurrency warnings

### Project Location
This is part of the Tuist ecosystem. The name "Cassiopeia" references Berlin (where Tuist was founded) and the Cassiopeia club.