//
//  DownloadGate.swift
//  DriftV2 / Slipstream
//
//  Bounded-concurrency gate. At most `capacity` downloads run at once;
//  extras queue FIFO until a slot frees. Cancellation-safe: a Task
//  cancelled while queued is removed and throws `CancellationError`
//  instead of holding a phantom slot.
//
//  Single instance per `Slipstream.install`. Shared by every
//  `PeerFirstLoader` (LLM, VLM, Whisper) so the cap is global across
//  model kinds.
//

import Foundation

actor DownloadGate {
    private let capacity: Int
    private var inUse = 0

    /// Waiters keyed by id so cancellation can pluck a specific one out.
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    /// FIFO order over `waiters.keys`. Maintained alongside `waiters`.
    private var order: [UUID] = []

    init(capacity: Int) {
        precondition(capacity > 0, "DownloadGate capacity must be positive")
        self.capacity = capacity
    }

    // MARK: - Public API

    /// Run `body` while holding one slot. Acquires before `body`, releases
    /// after — including on error and cancellation. The slot is released
    /// to the next FIFO waiter, or returned to the pool if none.
    func withSlot<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        try await acquire()
        do {
            let result = try await body()
            release()
            return result
        } catch {
            release()
            throw error
        }
    }

    /// Current pool occupancy. Exposed for tests/diagnostics only.
    var inFlightCount: Int { inUse }
    /// Current queue depth. Exposed for tests/diagnostics only.
    var queueDepth: Int { waiters.count }

    // MARK: - Internals

    private func acquire() async throws {
        try Task.checkCancellation()
        if inUse < capacity {
            inUse += 1
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                waiters[id] = cont
                order.append(id)
            }
        } onCancel: { [weak self] in
            // Hop onto the actor to mutate state safely.
            Task { await self?.cancelWaiter(id) }
        }
    }

    private func release() {
        // Hand the slot to the oldest waiter if any; otherwise return it
        // to the pool. Stale ids (already cancelled) won't appear in
        // `order` because `cancelWaiter` cleans both maps.
        while let nextID = order.first {
            order.removeFirst()
            if let cont = waiters.removeValue(forKey: nextID) {
                cont.resume()
                return
            }
            // If we ever fall through here it means `order` desynced from
            // `waiters` — shouldn't happen with correct usage, but the
            // loop drains gracefully.
        }
        inUse = max(0, inUse - 1)
    }

    private func cancelWaiter(_ id: UUID) {
        guard let cont = waiters.removeValue(forKey: id) else { return }
        order.removeAll { $0 == id }
        cont.resume(throwing: CancellationError())
    }
}
