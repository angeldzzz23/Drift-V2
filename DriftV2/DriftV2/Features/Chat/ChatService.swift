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
    let text: String
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
            continuation.finish(throwing: PeerError.remote("Chat service not yet wired."))
        }
    }
}
