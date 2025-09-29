# 🌌 Cassiopeia

A Swift remote CAS client for [swift-build](https://github.com/swiftlang/swift-build) that talks HTTP to your caching service.

> Cassiopeia’s name pays homage to Berlin—the city where Tuist was born—and to the Cassiopeia club that keeps the city dancing. This client aims to do the same for your builds: keep them moving fast.

## 📖 Overview

Cassiopeia packages the primitives that swift-build expects (`CASProtocol`, `ActionCacheProtocol`) and implements them on top of an HTTP contract. Point the client at a remote service (via `COMPILATION_CACHE_REMOTE_SERVICE_PATH`) and it will push/pull objects, query existence, and manage the action cache over the network.

## ✨ Features

- Swift-build compliant CAS + action-cache client
- Remote-only implementation that talks to an HTTP service
- Content-based addressing using SHA256 digests
- Minimal configuration: respects `COMPILATION_CACHE_REMOTE_SERVICE_PATH`
- Swift-native API design with async/await

## 🚀 Getting Started

### 📋 Prerequisites

- Xcode 15.0 or later
- Swift 5.9 or later
- macOS 14.0 or later (for development)

### 💻 Local Development Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/tuist/Cassiopeia.git
   cd Cassiopeia
   ```

2. **Open in Xcode**
   ```bash
   open Package.swift
   ```

3. **Build the project**
   ```bash
   swift build
   ```

4. **Run tests**
   ```bash
   swift test
   ```

### 📦 Using as a Dependency

Add Cassiopeia to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/tuist/Cassiopeia.git", from: "1.0.0")
]
```

Then add it as a dependency to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: ["Cassiopeia"]
)
```

## 🏗️ Architecture

The library centres around the `RemoteCAS` actor. It takes care of:

- Encoding `CASObject` payloads and reference lists into JSON
- Sending/receiving HTTP requests to the configured server
- Translating status codes and payloads into Swift errors or values

See [ARCHITECTURE.md](ARCHITECTURE.md) for the detailed HTTP contract the server is expected to implement. The same contract is also described in the root-level `cassiopeia-openapi.yaml` so you can feed it directly into tooling.

### Quick Usage

```swift
import Cassiopeia

// Explicit configuration
let remote = Cassiopeia.makeRemoteCAS(
    baseURL: URL(string: "https://cache.example.com/api")!,
    headers: ["Authorization": "Bearer <token>"]
)

// Or derive everything from the environment
// (expects COMPILATION_CACHE_REMOTE_SERVICE_PATH to be set)
let envBacked = try Cassiopeia.makeRemoteCASFromEnvironment()

// Store some bytes
let object = CASObject(string: "hello caches")
let id = try await remote.store(object: object)

// Later, look it up
if let restored = try await remote.load(id: id) {
    print(restored.data.stringValue ?? "")
}
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
