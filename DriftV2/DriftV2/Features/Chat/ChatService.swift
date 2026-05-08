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
        guard let store else { return ["status": "no-model"] }

        // Loading takes priority over a previously-loaded model — at the
        // start of `load(_:)` the previous loaded entry is dropped.
        if let loadingEntry = Catalog.all.first(where: {
            $0.kind == .llm && store.loadingEntryIds.contains($0.id)
        }) {
            return [
                "status": "loading",
                "model": loadingEntry.repoId,
                "displayName": loadingEntry.displayName,
            ]
        }

        guard let llm = store.loadedModels[.llm] as? LLMModel else {
            return ["status": "no-model"]
        }
        var meta: [String: String] = [
            "status": "ready",
            "model": llm.repoId,
        ]
        if let entry = Catalog.all.first(where: { $0.repoId == llm.repoId && $0.kind == .llm }) {
            meta["displayName"] = entry.displayName
            meta["sizeGB"] = String(format: "%.1f", entry.approxSizeGB)
            meta["minTier"] = entry.minTier.label
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
