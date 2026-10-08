import Foundation
import EVECLI

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// Foundation on Linux services Process termination handlers on its own thread,
// but FileHandle.readabilityHandler — which the capture pipeline uses for SSH's
// diagnostics — needs the dispatch main queue to be running. So the work runs
// on the main actor and the entry point parks here instead of returning.
Task { @MainActor in
    exit(await CLI.run(arguments: CommandLine.arguments))
}
dispatchMain()
