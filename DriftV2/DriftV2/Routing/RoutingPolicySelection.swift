//
//  BackendSelection.swift
//  DriftV2 / Routing
//
//  Kind-agnostic routing state. State is stored in dictionaries keyed by
//  `ServiceKind`, so adding a new model family is zero new code here —
//  just call `mode(for: ServiceKind("foo"))` and `resolve(kind: ...)`.
//
//  `resolve(...)` takes a `isLocallyReady: () -> Bool` closure rather
//  than reaching into ModelKit, so this file stays free of any
//  framework-specific dependencies. The caller (a feature view model)
//  knows how to ask "do we have it locally?" — the routing layer just
//  asks.
//

import Foundation
import Observation
import Peerly

@Observable
@MainActor
public final class RoutingPolicySelection {

    /// Mode per service kind. Defaults to `.auto` for kinds that have
    /// never been touched — Drift's preferred behavior is to offload
    /// when a peer's available.
    private var modes: [ServiceKind: AutoMode] = [:]

    /// Manual choice per service kind. Only consulted when
    /// `mode(for:)` is `.manual`. Defaults to `.local`.
    private var manualSources: [ServiceKind: Source] = [:]

    public init() {}

    // MARK: - Mode

    public func mode(for kind: ServiceKind) -> AutoMode {
        modes[kind] ?? .auto
    }

    public func setMode(_ mode: AutoMode, for kind: ServiceKind) {
        modes[kind] = mode
    }

    // MARK: - Manual source

    public func manualSource(for kind: ServiceKind) -> Source {
        manualSources[kind] ?? .local
    }

    /// Pin manual mode + local source. Manual choice is preserved when
    /// switching back from an auto mode.
    public func useLocal(for kind: ServiceKind) {
        modes[kind] = .manual
        manualSources[kind] = .local
    }

    public func useRemote(_ peer: Peer, for kind: ServiceKind) {
        modes[kind] = .manual
        manualSources[kind] = .remote(peerId: peer.id)
    }

    // MARK: - Manual selection queries (for highlighting in UI)

    public func isManuallySelectingLocal(for kind: ServiceKind) -> Bool {
        mode(for: kind) == .manual && manualSource(for: kind) == .local
    }

    public func isManuallySelectingRemote(_ peerId: Peer.ID, for kind: ServiceKind) -> Bool {
        mode(for: kind) == .manual && manualSource(for: kind) == .remote(peerId: peerId)
    }

    // MARK: - Resolution

    /// Live resolution of which source the next request for `kind`
    /// should hit. Returns `.unavailable` if nothing usable matches
    /// the current mode.
    public func resolve(
        kind: ServiceKind,
        isLocallyReady: () -> Bool,
        peerService: PeerService
    ) -> Resolution {
        switch mode(for: kind) {
        case .manual:
            switch manualSource(for: kind) {
            case .local:
                return isLocallyReady() ? .local : .unavailable
            case .remote(let peerId):
                guard peerService.connectedPeers.contains(where: { $0.id == peerId }),
                      Self.peerHasLoaded(serviceType: kind.id, peerId: peerId, in: peerService)
                else { return .unavailable }
                return .remote(peerId: peerId)
            }
        case .auto:
            // Prefer offloading to a peer; only fall back to local if
            // no peer is ready.
            for peer in peerService.connectedPeers {
                if Self.peerHasLoaded(serviceType: kind.id, peerId: peer.id, in: peerService) {
                    return .remote(peerId: peer.id)
                }
            }
            return isLocallyReady() ? .local : .unavailable
        case .autoBySpecs:
            return Self.bestBySpecs(
                serviceType: kind.id,
                peerService: peerService,
                isLocallyReady: isLocallyReady
            )
        }
    }

    // MARK: - Hello introspection (public so feature code can reuse it)

    /// True if the peer's hello reports a service of `serviceType` with
    /// at least one model whose `status == .loaded`.
    public static func peerHasLoaded(
        serviceType: String,
        peerId: Peer.ID,
        in peerService: PeerService
    ) -> Bool {
        peerService.peerHellos[peerId]?.services.contains { service in
            guard service.metadata["type"] == serviceType else { return false }
            guard let json = service.metadata["models"],
                  let data = json.data(using: .utf8),
                  let models = try? JSONDecoder().decode([ServiceModelInfo].self, from: data)
            else { return false }
            return models.contains { $0.status == .loaded }
        } ?? false
    }

    // MARK: - Internals

    /// v1 spec scoring: pick the candidate with the most RAM. Latency,
    /// thermal state, queue depth come later — they only need new logic
    /// here, the wire format already carries everything.
    private static func bestBySpecs(
        serviceType: String,
        peerService: PeerService,
        isLocallyReady: () -> Bool
    ) -> Resolution {
        var best: (Resolution, Int64)?
        if isLocallyReady() {
            best = (.local, peerService.myProfile.memoryBytes)
        }
        for peer in peerService.connectedPeers {
            guard peerHasLoaded(serviceType: serviceType, peerId: peer.id, in: peerService) else { continue }
            let memory = peerService.peerHellos[peer.id]?.profile?.memoryBytes ?? 0
            if best == nil || memory > best!.1 {
                best = (.remote(peerId: peer.id), memory)
            }
        }
        return best?.0 ?? .unavailable
    }
}
