//
//  SlipstreamEvent.swift
//  DriftV2 / Slipstream
//
//  Plain-value events emitted by PeerFirstLoader and SlipstreamService.
//  Consumed by UI (source labels), by SlipstreamRecorder (A/B benchmark
//  table), or by tests. No SwiftUI / no app types — keeps the module
//  package-extractable.
//

import Foundation

public nonisolated enum SlipstreamEvent: Sendable {
    /// A new model fetch is starting. `expectedBytes` is nil on the
    /// upstream path because HF progress is fractional, not byte-exact.
    case downloadStarted(repoId: String, source: Source, expectedBytes: UInt64?)

    /// Cumulative byte count for an in-flight transfer. Fired roughly
    /// once per chunk on the peer path; suppressed on the upstream path
    /// (existing fractional progress flows through ModelStore as before).
    case progress(repoId: String, bytes: UInt64, of: UInt64?)

    /// A peer rejected the request or the connection failed mid-transfer.
    /// The loader will try the next peer (or fall back to upstream)
    /// automatically — this event is informational.
    case peerFailed(repoId: String, peer: String, reason: String)

    /// Transfer completed. Wall time spans `downloadStarted → here`.
    /// For peer transfers, `bytes` is the verified-on-disk size.
    case downloadFinished(
        repoId: String,
        source: Source,
        bytes: UInt64,
        wallTime: TimeInterval
    )

    /// Final failure (no source produced bytes). Existing ModelStore
    /// error handling continues to surface this to the UI.
    case downloadFailed(repoId: String, reason: String)

    public nonisolated enum Source: Sendable, Hashable {
        case peer(name: String)
        case upstream
    }
}

extension SlipstreamEvent {
    public var repoId: String {
        switch self {
        case .downloadStarted(let r, _, _),
             .progress(let r, _, _),
             .peerFailed(let r, _, _),
             .downloadFinished(let r, _, _, _),
             .downloadFailed(let r, _):
            return r
        }
    }
}
