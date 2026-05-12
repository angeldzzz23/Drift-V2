//
//  SlipstreamContract.swift
//  DriftV2 / Slipstream
//
//  Wire schema for peer-to-peer model file transfer. Lives inside DriftV2
//  for now; folder is shaped as a future SPM package (`DriftSlipstream`)
//  with imports limited to Foundation + Peerly so extraction is mechanical.
//

import Foundation
import Peerly

/// A peer service that streams model weight files between devices on the
/// same Wi-Fi. Reuses Peerly's request → chunk* → done transport.
///
/// - `.manifest(repoId)` returns one `.manifest(files:)` and finishes.
/// - `.fetch(repoId, path, offset, length)` streams `.bytes(offset:data:)`
///   chunks until the requested range is delivered, then finishes.
public nonisolated enum SlipstreamContract: ServiceContract {
    public static let id = "drift.slipstream"
    public typealias Request = SlipstreamRequest
    public typealias Response = SlipstreamResponse
}

public nonisolated enum SlipstreamRequest: Codable, Sendable {
    /// Ask the host: what files does this repoId consist of?
    case manifest(repoId: String)
    /// Ask the host: stream me bytes of one file.
    case fetch(repoId: String, path: String, offset: UInt64, length: UInt64)
}

public nonisolated enum SlipstreamResponse: Codable, Sendable {
    /// Reply to `.manifest`. Empty `files` means "I don't have this repoId".
    case manifest(files: [FileEntry])
    /// Reply to `.fetch`. Yielded repeatedly with advancing offsets.
    case bytes(offset: UInt64, data: Data)
    /// Reply to `.fetch` when the host no longer has the requested repo
    /// (e.g., user deleted it between `manifest` and `fetch`).
    case notHave
}

/// One file in a model snapshot. Path is relative to the model's local
/// directory and uses forward slashes regardless of platform.
public nonisolated struct FileEntry: Codable, Sendable, Hashable {
    public let path: String
    public let size: UInt64
    /// Optional in v1; treated as "no integrity check available."
    /// v2 will populate from HuggingFace's per-file manifest.
    public let sha256: String?

    public init(path: String, size: UInt64, sha256: String? = nil) {
        self.path = path
        self.size = size
        self.sha256 = sha256
    }
}
