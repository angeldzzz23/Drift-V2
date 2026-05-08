//
//  HostActivityLog.swift
//  DriftV2
//
//  Captures incoming Peerly service calls served by THIS device — what
//  prompt arrived, who from, what we streamed back, terminal state. The
//  Hosted Activity sheet renders this live so you can watch your device
//  being used as a backend by another peer.
//

import Foundation
import Observation

struct HostSession: Identifiable, Hashable {
    enum Status: Hashable, Sendable {
        case running
        case finished
        case cancelled
        case failed(String)
    }

    let id: UUID
    let serviceID: String   // e.g. "drift.chat"
    let peerName: String
    /// Last user-role turn from the request, or whatever short summary
    /// the service chose. Used as a header in the UI.
    let prompt: String
    /// Concatenated chunks streamed back to the requester so far.
    var accumulated: String
    var status: Status
    let startedAt: Date
    var endedAt: Date?
}

@Observable
@MainActor
final class HostActivityLog {
    /// Capped ring of recent sessions, oldest first. UI typically renders
    /// reversed.
    private(set) var sessions: [HostSession] = []

    private let limit: Int

    init(limit: Int = 50) {
        self.limit = limit
    }

    @discardableResult
    func startSession(serviceID: String, peerName: String, prompt: String) -> UUID {
        let session = HostSession(
            id: UUID(),
            serviceID: serviceID,
            peerName: peerName,
            prompt: prompt,
            accumulated: "",
            status: .running,
            startedAt: Date(),
            endedAt: nil
        )
        sessions.append(session)
        if sessions.count > limit {
            sessions.removeFirst(sessions.count - limit)
        }
        return session.id
    }

    func append(_ chunk: String, to id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].accumulated += chunk
    }

    func finish(_ id: UUID) {
        update(id) { session in
            session.status = .finished
            session.endedAt = Date()
        }
    }

    func cancel(_ id: UUID) {
        update(id) { session in
            session.status = .cancelled
            session.endedAt = Date()
        }
    }

    func fail(_ id: UUID, message: String) {
        update(id) { session in
            session.status = .failed(message)
            session.endedAt = Date()
        }
    }

    func clear() {
        sessions.removeAll()
    }

    private func update(_ id: UUID, _ change: (inout HostSession) -> Void) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        change(&sessions[idx])
    }
}
