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
        guard let store else { return ["status": "no-model"] }

        if let loadingEntry = Catalog.all.first(where: {
            $0.kind == .whisper && store.loadingEntryIds.contains($0.id)
        }) {
            return [
                "status": "loading",
                "model": loadingEntry.repoId,
                "displayName": loadingEntry.displayName,
            ]
        }

        guard let whisper = store.loadedModels[.whisper] as? WhisperModel else {
            return ["status": "no-model"]
        }
        var meta: [String: String] = [
            "status": "ready",
            "model": whisper.repoId,
        ]
        if let entry = Catalog.all.first(where: { $0.repoId == whisper.repoId && $0.kind == .whisper }) {
            meta["displayName"] = entry.displayName
            meta["sizeGB"] = String(format: "%.1f", entry.approxSizeGB)
            meta["minTier"] = entry.minTier.label
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
