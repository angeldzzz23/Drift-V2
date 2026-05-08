//
//  ChatService.swift
//  DriftV2
//
//  Wire schema + host-side stub for the `drift.chat` Peerly service.
//  Metadata is computed live against `ModelStore` — but Peerly snapshots
//  it at register-time, so the App re-calls `peerService.register(...)`
//  on `.loaded` / `.unloaded` events to push fresh metadata to peers.
//

import Foundation
import Peerly
import ModelKit
import ModelKitMLX

// MARK: - Wire types

nonisolated struct ChatRequest: Codable, Sendable {
    /// Full conversation history including the new user prompt as the
    /// last turn. The host applies this verbatim to the loaded LLM.
    let turns: [Turn]

    nonisolated struct Turn: Codable, Sendable {
        /// `system` / `user` / `assistant`. Matches `ChatTurn.Role.rawValue`.
        let role: String
        let content: String
    }
}

nonisolated struct ChatChunk: Codable, Sendable {
    let text: String
}

nonisolated enum ChatContract: ServiceContract {
    static let id = "drift.chat"
    typealias Request = ChatRequest
    typealias Response = ChatChunk
}

// MARK: - Host stub

@MainActor
final class ChatService: Service {
    typealias Contract = ChatContract

    private weak var store: ModelStore?

    init(store: ModelStore) {
        self.store = store
    }

    /// Snapshotted by Peerly at every `peerService.register(self)` call.
    /// Re-register from app code to refresh.
    var metadata: [String: String] {
        var meta: [String: String] = ["type": "llm"]
        guard let store else { return meta }

        let loadedRepoId = (store.loadedModels[.llm] as? LLMModel)?.repoId

        let models: [ServiceModelInfo] = Catalog.all
            .filter { $0.kind == .llm && store.isDownloaded($0) }
            .sorted(by: { $0.displayName < $1.displayName })
            .map { entry in
                let status: ServiceModelInfo.Status =
                    store.loadingEntryIds.contains(entry.id) ? .loading
                    : entry.repoId == loadedRepoId ? .loaded
                    : .idle
                return ServiceModelInfo(
                    id: entry.repoId,
                    name: entry.displayName,
                    sizeGB: entry.approxSizeGB,
                    minTier: entry.minTier.label,
                    status: status
                )
            }

        if let data = try? JSONEncoder().encode(models),
           let json = String(data: data, encoding: .utf8) {
            meta["models"] = json
        }
        return meta
    }

    func handle(
        _ request: ChatRequest,
        context: ServiceCallContext
    ) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor [weak store] in
                guard let store else {
                    continuation.finish(throwing: PeerError.remote("Host store gone."))
                    return
                }
                guard let llm = store.loadedModels[.llm] as? LLMModel else {
                    continuation.finish(throwing: PeerError.remote("No LLM loaded on host."))
                    return
                }
                let turns = request.turns.compactMap { wire -> ChatTurn? in
                    guard let role = ChatTurn.Role(rawValue: wire.role) else { return nil }
                    return ChatTurn(role: role, content: wire.content)
                }
                guard !turns.isEmpty else {
                    continuation.finish(throwing: PeerError.remote("Empty conversation."))
                    return
                }
                do {
                    let stream = try await llm.stream(turns: turns)
                    for await chunk in stream {
                        if Task.isCancelled { break }
                        continuation.yield(ChatChunk(text: chunk))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
