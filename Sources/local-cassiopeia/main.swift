import Foundation
import Cassiopeia
import SWBUtil

enum Command: String, CaseIterable {
    case store
    case load
    case list
    case contains
    case delete
    case cache
    case lookupCache = "lookup-cache"
    case help

    var description: String {
        switch self {
        case .store:
            return "Store data in CAS"
        case .load:
            return "Load data from CAS by ID"
        case .list:
            return "List all objects in CAS"
        case .contains:
            return "Check if object exists in CAS"
        case .delete:
            return "Delete object from CAS"
        case .cache:
            return "Cache an object ID for a key"
        case .lookupCache:
            return "Lookup cached object for a key"
        case .help:
            return "Show help message"
        }
    }
}

func printUsage() {
    print("Usage: cassiopeia [--cas-path PATH] COMMAND [ARGS...]")
    print("")
    print("A Content Addressable Storage (CAS) tool")
    print("")
    print("Options:")
    print("  --cas-path PATH    Path to CAS directory (default: ~/.cassiopeia)")
    print("")
    print("Commands:")
    for command in Command.allCases {
        print("  \(command.rawValue.padding(toLength: 15, withPad: " ", startingAt: 0)) \(command.description)")
    }
    print("")
    print("Examples:")
    print("  cassiopeia store file.txt           # Store a file and get its ID")
    print("  cassiopeia store --data 'text'      # Store text data")
    print("  cassiopeia load <id>                # Load object by ID")
    print("  cassiopeia list                     # List all stored objects")
    print("  cassiopeia contains <id>            # Check if object exists")
    print("  cassiopeia delete <id>              # Delete object")
    print("  cassiopeia cache <key> <object-id>  # Cache object ID for key")
    print("  cassiopeia lookup-cache <key>       # Lookup cached object")
}

func parseArguments() -> (casPath: String, command: Command?, args: [String]) {
    let arguments = CommandLine.arguments
    var casPath = NSString(string: "~/.cassiopeia").expandingTildeInPath
    var commandIndex = 1

    if arguments.count > 2 && arguments[1] == "--cas-path" {
        casPath = NSString(string: arguments[2]).expandingTildeInPath
        commandIndex = 3
    }

    guard commandIndex < arguments.count else {
        return (casPath, nil, [])
    }

    let command = Command(rawValue: arguments[commandIndex])
    let args = Array(arguments[(commandIndex + 1)...])

    return (casPath, command, args)
}

@main
struct CassiopeiaExecutable {
    static func main() async {
        let (casPath, command, args) = parseArguments()

        guard let command = command else {
            printUsage()
            exit(1)
        }

        if command == .help {
            printUsage()
            exit(0)
        }

        let cas = FileSystemCAS(path: casPath)
        let cache = FileSystemActionCache(path: casPath)

        do {
            switch command {
            case .store:
                try await handleStore(cas: cas, args: args)

            case .load:
                guard args.count == 1 else {
                    print("Error: 'load' requires exactly one argument (object ID)")
                    exit(1)
                }
                try await handleLoad(cas: cas, id: args[0])

            case .list:
                try await handleList(cas: cas)

            case .contains:
                guard args.count == 1 else {
                    print("Error: 'contains' requires exactly one argument (object ID)")
                    exit(1)
                }
                try await handleContains(cas: cas, id: args[0])

            case .delete:
                guard args.count == 1 else {
                    print("Error: 'delete' requires exactly one argument (object ID)")
                    exit(1)
                }
                try await handleDelete(cas: cas, id: args[0])

            case .cache:
                guard args.count == 2 else {
                    print("Error: 'cache' requires exactly two arguments (key and object ID)")
                    exit(1)
                }
                try await handleCache(cache: cache, key: args[0], objectID: args[1])

            case .lookupCache:
                guard args.count == 1 else {
                    print("Error: 'lookup-cache' requires exactly one argument (key)")
                    exit(1)
                }
                try await handleLookupCache(cache: cache, key: args[0])

            case .help:
                break
            }
        } catch {
            print("Error: \(error)")
            exit(1)
        }
    }

    static func handleStore(cas: FileSystemCAS, args: [String]) async throws {
        let data: Data

        if args.count == 2 && args[0] == "--data" {
            data = args[1].data(using: .utf8) ?? Data()
        } else if args.count == 1 {
            let url = URL(fileURLWithPath: args[0])
            data = try Data(contentsOf: url)
        } else {
            print("Error: 'store' requires either a file path or --data 'content'")
            exit(1)
        }

        let object = CASObject(data: data)
        let id = try await cas.store(object: object)
        print(id.hash)
    }

    static func handleLoad(cas: FileSystemCAS, id: String) async throws {
        let dataID = DataID(hash: id)
        if let object = try await cas.load(id: dataID) {
            let data = Data(object.data.bytes)
            if let output = FileHandle.standardOutput as? FileHandle {
                output.write(data)
            }
        } else {
            print("Error: Object not found")
            exit(1)
        }
    }

    static func handleList(cas: FileSystemCAS) async throws {
        let objects = try await cas.listObjects()
        for object in objects {
            print(object.hash)
        }
    }

    static func handleContains(cas: FileSystemCAS, id: String) async throws {
        let dataID = DataID(hash: id)
        let exists = try await cas.contains(id: dataID)
        print(exists ? "true" : "false")
    }

    static func handleDelete(cas: FileSystemCAS, id: String) async throws {
        let dataID = DataID(hash: id)
        try await cas.delete(id: dataID)
        print("Deleted: \(id)")
    }

    static func handleCache(cache: FileSystemActionCache, key: String, objectID: String) async throws {
        let keyID = DataID(hash: key)
        let objID = DataID(hash: objectID)
        try await cache.cache(objectID: objID, forKeyID: keyID)
        print("Cached: \(objectID) for key: \(key)")
    }

    static func handleLookupCache(cache: FileSystemActionCache, key: String) async throws {
        let keyID = DataID(hash: key)
        if let objectID = try await cache.lookupCachedObject(for: keyID) {
            print(objectID.hash)
        } else {
            print("Not found")
            exit(1)
        }
    }
}