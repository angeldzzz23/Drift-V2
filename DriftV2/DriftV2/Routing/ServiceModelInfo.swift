//
//  ServiceModelInfo.swift
//  DriftV2 / Routing
//
//  Wire shape for a single model entry advertised by a service via
//  `ServiceCapability.metadata["models"]` (JSON-encoded array). Same
//  schema regardless of `type` (llm, whisper, vlm…) — peers always
//  decode the same struct.
//

import Foundation

public struct ServiceModelInfo: Codable, Sendable, Hashable {
    public enum Status: String, Codable, Sendable, Hashable {
        /// Downloaded, not in memory.
        case idle
        /// Currently being brought into memory.
        case loading
        /// In memory and usable.
        case loaded
    }

    /// HuggingFace repo id (or WhisperKit variant name).
    public let id: String
    /// Friendly display name from the local catalog.
    public let name: String
    public let sizeGB: Double
    /// `Phone`, `iPhone / iPad`, etc.
    public let minTier: String
    public let status: Status

    public init(
        id: String,
        name: String,
        sizeGB: Double,
        minTier: String,
        status: Status
    ) {
        self.id = id
        self.name = name
        self.sizeGB = sizeGB
        self.minTier = minTier
        self.status = status
    }
}
