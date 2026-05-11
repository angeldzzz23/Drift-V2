//
//  SlipstreamConfig.swift
//  DriftV2 / Slipstream
//
//  Knobs the host app sets to control peer-vs-upstream behavior. The
//  primary purpose is A/B testing: flip `.mode` to compare LAN transfer
//  against the existing HuggingFace path on the same binary.
//

import Foundation
import Observation

@Observable
@MainActor
public final class SlipstreamConfig {
    public enum Mode: String, Sendable, CaseIterable, Identifiable {
        /// Try peers first; fall back to upstream (HF). Production default.
        case peerFirstThenUpstream
        /// Peers only; fail if no peer has the model. Use for benchmarking
        /// the LAN path in isolation.
        case peerOnly
        /// Skip peers entirely; always upstream. Use as the A/B baseline.
        case upstreamOnly

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .peerFirstThenUpstream: return "Peer first → upstream"
            case .peerOnly:              return "Peers only"
            case .upstreamOnly:          return "Upstream only"
            }
        }
    }

    /// Source-selection policy. Read on every `startDownload`.
    public var mode: Mode

    /// Size of each `.bytes` chunk yielded by the host. 1 MB is a balanced
    /// LAN default — large enough to amortize envelope overhead, small
    /// enough that progress feels live.
    public var chunkSize: Int

    /// How many peers to pull from in parallel for a single model.
    /// v1 always behaves as 1; the field reserves the wire for v2.
    public var parallelPeers: Int

    /// Whether this device replies with real manifests when peers ask.
    /// When `false`, the host service replies `.manifest(files: [])` so
    /// callers move on without your bandwidth.
    public var sharesWeights: Bool

    private static let modeKey = "DriftV2.Slipstream.mode"
    private static let sharesKey = "DriftV2.Slipstream.sharesWeights"

    public init(
        mode: Mode? = nil,
        chunkSize: Int = 1 << 20,
        parallelPeers: Int = 1,
        sharesWeights: Bool? = nil
    ) {
        let defaults = UserDefaults.standard
        self.mode = mode
            ?? (defaults.string(forKey: Self.modeKey).flatMap(Mode.init(rawValue:)))
            ?? .peerFirstThenUpstream
        self.chunkSize = chunkSize
        self.parallelPeers = parallelPeers
        if let sharesWeights {
            self.sharesWeights = sharesWeights
        } else if defaults.object(forKey: Self.sharesKey) != nil {
            self.sharesWeights = defaults.bool(forKey: Self.sharesKey)
        } else {
            self.sharesWeights = true
        }
    }

    /// Call from UI when the toggle flips so the next launch picks the
    /// same setting. Cheap; no migration needed.
    public func persist() {
        let defaults = UserDefaults.standard
        defaults.set(mode.rawValue, forKey: Self.modeKey)
        defaults.set(sharesWeights, forKey: Self.sharesKey)
    }
}
