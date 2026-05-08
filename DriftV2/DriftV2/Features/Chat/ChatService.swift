//
//  ChatService.swift
//  DriftV2
//
//  Wire schema + host-side stub for the `drift.chat` Peerly service.
//  Registering a `ChatService()` instance with `PeerService` is what
//  makes "drift.chat" appear in this device's hello payload and TXT
//  record. The handler is intentionally stubbed — actual generation is
//  still local-only via `ChatViewModel.send(using:)`.
//

import Foundation
import Peerly

// MARK: - Wire types

nonisolated struct ChatRequest: Codable, Sendable {
    let text: String
}

nonisolated struct ChatChunk: Codable, Sendable {
    let text: String
}

nonisolated enum ChatContract: ServiceContract {
    static let id = "drift.chat"
    typealias Request = ChatRequest
    typealias Response = ChatChunk
}

// MARK: - Host stub

@MainActor
final class ChatService: Service {
    typealias Contract = ChatContract

    var metadata: [String: String] {
        ["status": "stub"]
    }

    func handle(
        _ request: ChatRequest,
        context: ServiceCallContext
    ) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: PeerError.remote("Chat service not yet wired."))
        }
    }
}
