//
//  TranscribeService.swift
//  DriftV2
//
//  Wire schema + host-side stub for the `drift.transcribe` Peerly
//  service. Metadata advertises whether a Whisper model is currently
//  loaded — Peerly snapshots metadata at register-time, so the App
//  re-calls `peerService.register(...)` on `.loaded` / `.unloaded`
//  events for `.whisper` to push fresh metadata to peers.
//

import Foundation
import Peerly
import ModelKit
import ModelKitWhisper

// MARK: - Wire types

nonisolated struct TranscribeRequest: Codable, Sendable {
    /// Raw audio bytes (m4a / wav / mp3 — anything WhisperKit accepts).
    let audio: Data
}

nonisolated struct TranscribeChunk: Codable, Sendable {
    let text: String
}

nonisolated enum TranscribeContract: ServiceContract {
    static let id = "drift.transcribe"
    typealias Request = TranscribeRequest
    typealias Response = TranscribeChunk
}

// MARK: - Host stub

@MainActor
final class TranscribeService: Service {
    typealias Contract = TranscribeContract

    private weak var store: ModelStore?

    init(store: ModelStore) {
        self.store = store
    }

    var metadata: [String: String] {
        var meta: [String: String] = ["type": "whisper"]
        guard let store else { return meta }

        let loadedRepoId = (store.loadedModels[.whisper] as? WhisperModel)?.repoId

        let models: [ServiceModelInfo] = Catalog.all
            .filter { $0.kind == .whisper && store.isDownloaded($0) }
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
        _ request: TranscribeRequest,
        context: ServiceCallContext
    ) -> AsyncThrowingStream<TranscribeChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: PeerError.remote("Transcribe service not yet wired."))
        }
    }
}
