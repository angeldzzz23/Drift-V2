//
//  ServiceModelInfo.swift
//  DriftV2
//
//  Wire-shape for one model entry advertised by a service. Both
//  `ChatService` and `TranscribeService` JSON-encode `[ServiceModelInfo]`
//  under the `models` metadata key, so peers always know how to parse the
//  inventory regardless of the service `type`.
//

import Foundation

nonisolated struct ServiceModelInfo: Codable, Sendable, Hashable {
    enum Status: String, Codable, Sendable, Hashable {
        /// Downloaded, not in memory.
        case idle
        /// Currently being brought into memory.
        case loading
        /// In memory and usable.
        case loaded
    }

    /// HuggingFace repo id (or WhisperKit variant name).
    let id: String
    /// Friendly display name from the local catalog.
    let name: String
    let sizeGB: Double
    /// `Phone`, `iPhone / iPad`, etc.
    let minTier: String
    let status: Status
}
