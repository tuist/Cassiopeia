# Cassiopeia Architecture

## Overview

Cassiopeia is now a remote-first Content Addressable Storage (CAS) client. The library speaks a small HTTP-based protocol to a backing CAS service and exposes the same Swift-facing primitives (`CASProtocol`, `ActionCacheProtocol`) that swift-build expects. All persistence and deduplication lives on the server side – Cassiopeia focuses on reliably shuttling data between the build system and that service. The protocol is mirrored in the root-level OpenAPI specification `cassiopeia-openapi.yaml`.

The remote endpoint to talk to is discovered via the `COMPILATION_CACHE_REMOTE_SERVICE_PATH` environment variable. When present, `Cassiopeia.makeRemoteCASFromEnvironment()` builds a `RemoteCAS` instance that routes all requests to the configured URL.

## Library Components

- **`CASProtocol`** – Shared interface for storing, loading, deleting, and checking CAS objects.
- **`ActionCacheProtocol`** – Interface for associating action keys with result objects.
- **`CASObject`** – Value type that carries the serialized payload (`ByteString`) and referenced `DataID`s.
- **`DataID`** – SHA256-derived digest wrapper used throughout the API.
- **`RemoteCAS`** – Actor that implements both protocols on top of HTTP. It converts `CASObject` structures into network payloads, enforces expected status codes, and turns response bodies back into high-level types.
- **`RemoteCASConfiguration`** – Bundles the base service URL, the `URLSession` that should be used for transport, and any default headers (for example authentication tokens).
- **`Cassiopeia.makeRemoteCAS`** – Convenience factory to produce a `RemoteCAS` with the desired configuration or derive one from process environment.

All operations are asynchronous and leverage Swift's `URLSession`. Errors are surfaced as `RemoteCASError` values, distinguishing transport problems, invalid responses, and HTTP status code failures.

## Environment Integration

Cassiopeia does not interpret build settings beyond `COMPILATION_CACHE_REMOTE_SERVICE_PATH`. When that environment variable is set to an absolute HTTP(S) URL, the library uses it as the base URL for every call. If the variable is missing or not a valid HTTP URL, `Cassiopeia.makeRemoteCASFromEnvironment` throws a `CassiopeiaFactoryError` describing the issue.

## HTTP Contract

All requests target the configured base URL. The tables below show paths relative to that base. Bodies are JSON encoded with UTF-8. Binary object contents are base64 encoded.

### CAS Objects

| Operation | Method | Path | Request Body | Success Response |
|-----------|--------|------|--------------|------------------|
| Store object | `POST` | `/cas/objects` | `{ "data": "<base64>", "refs": ["<data-id>", ...] }` | `201 Created` with body `{ "id": "<data-id>" }`
| Load object | `GET` | `/cas/objects/{data-id}` | _none_ | `200 OK` with `{ "data": "<base64>", "refs": ["<data-id>", ...] }` |
| Contains object | `HEAD` | `/cas/objects/{data-id}` | _none_ | `200 OK` if present, `404 Not Found` otherwise |
| Delete object | `DELETE` | `/cas/objects/{data-id}` | _none_ | `204 No Content` (deleting a non-existent object should still reply with `204` or `404`) |

### Action Cache

| Operation | Method | Path | Request Body | Success Response |
|-----------|--------|------|--------------|------------------|
| Store mapping | `PUT` | `/cas/action-cache/{key-id}` | `{ "object_id": "<data-id>" }` | `204 No Content` |
| Lookup mapping | `GET` | `/cas/action-cache/{key-id}` | _none_ | `200 OK` with `{ "object_id": "<data-id>" }` or `404 Not Found` |

### Error Semantics

- `400–499` responses are surfaced as `RemoteCASError.serverError` with the status code and any textual payload.
- `500–599` responses also map to `RemoteCASError.serverError` and should be treated as retryable by higher layers.
- Connection or TLS failures become `RemoteCASError.transportError`.
- Malformed JSON or invalid base64 payloads become `RemoteCASError.decodingFailed` / `RemoteCASError.encodingFailed`.

### Headers

`RemoteCAS` sends any headers specified in the configuration on every request (for example `Authorization`). Additional per-call headers can be injected when needed.

### Byte Encoding

Binary object data is **always** base64 encoded to ensure the payload remains JSON friendly. References are serialized as their hex string digests. The server must return the same representation when serving objects.

## Threading & Concurrency

`RemoteCAS` is an actor. Each network call is awaited in isolation and translates its result back onto the calling task. The tests use a custom `URLProtocol` to simulate the remote server. If you add new HTTP operations, update both the test harness and this contract to stay in sync.
