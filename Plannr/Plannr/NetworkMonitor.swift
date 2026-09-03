//
//  NetworkMonitor.swift
//  Plannr
//
//  Publishes coarse connectivity and fires `onReconnect` when the network comes
//  back after being down — the cue to retry syncs that gave up earlier.
//

import Foundation
import Network

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var isOnline = true

    /// Invoked once on each offline → online transition.
    var onReconnect: (() -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.matthewblanke.plannr.network-monitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let cameBack = online && !self.isOnline
                self.isOnline = online
                if cameBack { self.onReconnect?() }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
