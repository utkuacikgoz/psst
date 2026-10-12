import Foundation
import Network

/// iOS's own view of whether there's a usable network, as it changes.
enum NetworkWatcher {
    static func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in continuation.yield(path.status == .satisfied) }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "psst.network"))
        }
    }
}
