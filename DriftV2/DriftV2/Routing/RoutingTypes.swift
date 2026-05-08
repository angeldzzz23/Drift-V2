//
//  RoutingTypes.swift
//  DriftV2 / Routing
//
//  Library-shaped, model-agnostic routing primitives. All kinds are
//  identified by a stable string `ServiceKind.id` that matches the
//  `metadata["type"]` field a service advertises in Peerly's hello —
//  so adding a new model family (vlm, embeddings, …) requires no
//  changes to this file.
//
//  Designed so this folder can later be lifted into its own Swift
//  Package (`DriftRouting`) with no app-specific dependencies. Today it
//  imports only Foundation + Peerly.
//

import Foundation
import Peerly

/// Stable identifier for a class of model/service. Matches the `type`
/// metadata field on `ServiceCapability`. Construct with the same string
/// the service advertises so resolution lines up.
public struct ServiceKind: Hashable, Sendable {
    public let id: String
    public init(_ id: String) { self.id = id }

    public static let llm = ServiceKind("llm")
    public static let whisper = ServiceKind("whisper")
    public static let vlm = ServiceKind("vlm")
}

/// How requests of a given kind are routed.
public enum AutoMode: String, Hashable, Sendable, CaseIterable {
    /// Caller pinned a specific source (.local or .remote(peer)).
    case manual
    /// Pick the first reachable peer with the model loaded; fall back
    /// to local if loaded.
    case auto
    /// Pick the candidate with the best hardware (RAM today; latency,
    /// thermal, queue depth on the roadmap) among everyone with the
    /// model loaded.
    case autoBySpecs

    public var label: String {
        switch self {
        case .manual:      return "Manual"
        case .auto:        return "Auto"
        case .autoBySpecs: return "Auto + Specs"
        }
    }
}

/// A pinned manual choice for a service kind.
public enum Source: Hashable, Sendable {
    case local
    case remote(peerId: Peer.ID)
}

/// What `BackendSelection.resolve(...)` returns: the live decision
/// after consulting peer state. `.unavailable` means no candidate is
/// ready in the selected mode.
public enum Resolution: Hashable, Sendable {
    case local
    case remote(peerId: Peer.ID)
    case unavailable
}
