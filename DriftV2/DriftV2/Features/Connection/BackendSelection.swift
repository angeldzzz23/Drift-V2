//
//  BackendSelection.swift
//  DriftV2
//
//  Routing preferences: which device should serve chat (and later
//  transcription)? Set from the Connections sheet, read by Chat.
//

import Foundation
import Observation
import Peerly

@Observable
@MainActor
final class BackendSelection {
    enum LLMSource: Hashable, Sendable {
        case local
        case remote(peerId: Peer.ID)
    }

    /// Where chat sends should be routed. Defaults to local.
    var llm: LLMSource = .local

    var isUsingLocalLLM: Bool {
        if case .local = llm { return true }
        return false
    }

    func isUsingRemoteLLM(on peerId: Peer.ID) -> Bool {
        if case .remote(let id) = llm { return id == peerId }
        return false
    }

    func useLocalLLM() {
        llm = .local
    }

    func useRemoteLLM(on peer: Peer) {
        llm = .remote(peerId: peer.id)
    }
}
