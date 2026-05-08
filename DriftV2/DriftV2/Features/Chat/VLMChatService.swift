//
//  VLMChatService.swift
//  DriftV2
//
//  Vision-capable chat host. Same wire schema as `ChatService`
//  (`ChatRequest` / `ChatChunk`), different service id (`drift.vlm`)
//  and a different `metadata["type"]` ("vlm" vs "llm") so the routing
//  layer can pick it up independently. Reaches into `ModelStore` for a
//  loaded `VLMModel` and runs the request — including any image bytes
//  carried by `ChatRequest.images` — through
//  `VLMModel.stream(turns:images:)`.
//

import Foundation
import Peerly
import ModelKit
import ModelKitMLX

@MainActor
final class VLMChatService: Service {
    typealias Contract = VLMChatContract

    private weak var store: ModelStore?
    private weak var activityLog: HostActivityLog?

    init(store: ModelStore, activityLog: HostActivityLog? = nil) {
        self.store = store
        self.activityLog = activityLog
    }

    var metadata: [String: String] {
        var meta: [String: String] = ["type": "vlm"]
        guard let store else { return meta }

        let loadedRepoId = (store.loadedModels[.vlm] as? VLMModel)?.repoId

        let models: [ServiceModelInfo] = Catalog.all
            .filter { $0.kind == .vlm && store.isDownloaded($0) }
            .sorted(by: { $0.displayName < $1.displayName })
            .map { entry in
                let status: ServiceModelInfo.Status =
                    store.loadingEntryIds.contains(entry.id) ? .loading
                    : entry.repoId == loadedRepoId ? .loaded
                    : .idle
                return ServiceModelInfo(
                    id: entry.repoId,
                    name: entry.displayName,
                    sizeGB: entry.approxSizeGB,
                    minTier: entry.minTier.label,
                    status: status
                )
            }

        if let data = try? JSONEncoder().encode(models),
           let json = String(data: data, encoding: .utf8) {
            meta["models"] = json
        }
        return meta
    }

    func handle(
        _ request: ChatRequest,
        context: ServiceCallContext
    ) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor [weak store, weak activityLog] in
                guard let store else {
                    continuation.finish(throwing: PeerError.remote("Host store gone."))
                    return
                }
                guard let vlm = store.loadedModels[.vlm] as? VLMModel else {
                    continuation.finish(throwing: PeerError.remote("No VLM loaded on host."))
                    return
                }
                let turns = request.turns.compactMap { wire -> ChatTurn? in
                    guard let role = ChatTurn.Role(rawValue: wire.role) else { return nil }
                    return ChatTurn(role: role, content: wire.content)
                }
                guard !turns.isEmpty else {
                    continuation.finish(throwing: PeerError.remote("Empty conversation."))
                    return
                }

                let lastUserPrompt = request.turns.last(where: { $0.role == "user" })?.content ?? ""
                let imageSummary = request.images.isEmpty
                    ? lastUserPrompt
                    : "\(request.images.count) image(s) · \(lastUserPrompt)"
                let sessionId = activityLog?.startSession(
                    serviceID: VLMChatContract.id,
                    peerName: context.peer.displayName,
                    prompt: imageSummary
                )

                do {
                    let stream = try await vlm.stream(turns: turns, images: request.images)
                    for await chunk in stream {
                        if Task.isCancelled { break }
                        continuation.yield(ChatChunk(text: chunk))
                        if let sessionId {
                            activityLog?.append(chunk, to: sessionId)
                        }
                    }
                    continuation.finish()
                    if let sessionId { activityLog?.finish(sessionId) }
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                    if let sessionId { activityLog?.cancel(sessionId) }
                } catch {
                    continuation.finish(throwing: error)
                    if let sessionId { activityLog?.fail(sessionId, message: error.localizedDescription) }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
