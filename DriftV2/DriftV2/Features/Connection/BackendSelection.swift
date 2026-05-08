//
//  BackendSelection.swift
//  DriftV2
//
//  Routing preferences: which device should serve chat (and later
//  transcription)? Set from the Connections sheet, read by Chat.
//
//  Three modes per service kind:
//    - .manual          — caller pinned a specific source (.local or .remote(peer))
//    - .auto            — pick the first available peer with the model loaded;
//                         fall back to local if loaded
//    - .autoBySpecs     — pick the candidate with the most memory among
//                         everyone (local + connected peers) that has the
//                         model loaded
//
//  In auto modes, `manualLLM` / `manualWhisper` is preserved so that
//  switching back to .manual restores the prior choice.
//

import Foundation
import Observation
import ModelKit
import Peerly

@Observable
@MainActor
final class BackendSelection {
    enum AutoMode: String, Hashable, Sendable, CaseIterable {
        case manual
        case auto
        case autoBySpecs

        var label: String {
            switch self {
            case .manual:       return "Manual"
            case .auto:         return "Auto"
            case .autoBySpecs:  return "Auto + Specs"
            }
        }
    }

    enum LLMSource: Hashable, Sendable {
        case local
        case remote(peerId: Peer.ID)
    }

    enum WhisperSource: Hashable, Sendable {
        case local
        case remote(peerId: Peer.ID)
    }

    /// Resolved choice — what `currentBackend` should actually use right
    /// now, after consulting state.
    enum Resolution: Hashable, Sendable {
        case local
        case remote(peerId: Peer.ID)
        case unavailable
    }

    // MARK: - LLM

    var llmMode: AutoMode = .auto
    /// Only consulted when `llmMode == .manual`.
    var manualLLM: LLMSource = .local

    // MARK: - Whisper

    var whisperMode: AutoMode = .auto
    /// Only consulted when `whisperMode == .manual`.
    var manualWhisper: WhisperSource = .local

    // MARK: - Manual setters (used by per-service "Use for X" buttons)

    func useLocalLLM() {
        llmMode = .manual
        manualLLM = .local
    }

    func useRemoteLLM(on peer: Peer) {
        llmMode = .manual
        manualLLM = .remote(peerId: peer.id)
    }

    func useLocalWhisper() {
        whisperMode = .manual
        manualWhisper = .local
    }

    func useRemoteWhisper(on peer: Peer) {
        whisperMode = .manual
        manualWhisper = .remote(peerId: peer.id)
    }

    // MARK: - Manual selection queries (only meaningful in .manual mode)

    var isManuallyUsingLocalLLM: Bool {
        llmMode == .manual && manualLLM == .local
    }

    func isManuallyUsingRemoteLLM(on peerId: Peer.ID) -> Bool {
        llmMode == .manual && manualLLM == .remote(peerId: peerId)
    }

    var isManuallyUsingLocalWhisper: Bool {
        whisperMode == .manual && manualWhisper == .local
    }

    func isManuallyUsingRemoteWhisper(on peerId: Peer.ID) -> Bool {
        whisperMode == .manual && manualWhisper == .remote(peerId: peerId)
    }

    // MARK: - Resolution

    /// Live resolution of which source the next LLM request should hit.
    /// Returns `.unavailable` if nothing usable matches the mode.
    func resolveLLM(store: ModelStore, peerService: PeerService) -> Resolution {
        switch llmMode {
        case .manual:
            switch manualLLM {
            case .local:
                return store.loadedModels[.llm] != nil ? .local : .unavailable
            case .remote(let peerId):
                guard peerService.connectedPeers.contains(where: { $0.id == peerId }),
                      Self.peerHasLoaded(serviceType: "llm", peerId: peerId, in: peerService)
                else { return .unavailable }
                return .remote(peerId: peerId)
            }
        case .auto:
            // Prefer offloading to a peer; only fall back to local if no
            // peer is ready.
            for peer in peerService.connectedPeers {
                if Self.peerHasLoaded(serviceType: "llm", peerId: peer.id, in: peerService) {
                    return .remote(peerId: peer.id)
                }
            }
            return store.loadedModels[.llm] != nil ? .local : .unavailable
        case .autoBySpecs:
            return Self.bestBySpecs(
                serviceType: "llm",
                store: store,
                peerService: peerService,
                isLocalReady: { store.loadedModels[.llm] != nil }
            )
        }
    }

    func resolveWhisper(store: ModelStore, peerService: PeerService) -> Resolution {
        switch whisperMode {
        case .manual:
            switch manualWhisper {
            case .local:
                return store.loadedModels[.whisper] != nil ? .local : .unavailable
            case .remote(let peerId):
                guard peerService.connectedPeers.contains(where: { $0.id == peerId }),
                      Self.peerHasLoaded(serviceType: "whisper", peerId: peerId, in: peerService)
                else { return .unavailable }
                return .remote(peerId: peerId)
            }
        case .auto:
            for peer in peerService.connectedPeers {
                if Self.peerHasLoaded(serviceType: "whisper", peerId: peer.id, in: peerService) {
                    return .remote(peerId: peer.id)
                }
            }
            return store.loadedModels[.whisper] != nil ? .local : .unavailable
        case .autoBySpecs:
            return Self.bestBySpecs(
                serviceType: "whisper",
                store: store,
                peerService: peerService,
                isLocalReady: { store.loadedModels[.whisper] != nil }
            )
        }
    }

    // MARK: - Internals

    /// Among everyone (local + connected peers) that has `serviceType`
    /// loaded, pick the one with the most RAM. v1 scoring; latency,
    /// thermal state, queue depth come later.
    private static func bestBySpecs(
        serviceType: String,
        store: ModelStore,
        peerService: PeerService,
        isLocalReady: () -> Bool
    ) -> Resolution {
        var best: (Resolution, Int64)?
        if isLocalReady() {
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

    /// True if the peer's hello reports a service of `serviceType` with
    /// at least one model whose `status == .loaded`.
    static func peerHasLoaded(
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
}
