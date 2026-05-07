//
//  ChatViewModel.swift
//  DriftV2
//

import Foundation
import Observation
import os
import ModelKit
import ModelKitMLX

struct ChatMessage: Identifiable, Hashable {
    let id = UUID()
    let role: ChatTurn.Role
    var text: String
}

@Observable
@MainActor
final class ChatViewModel {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DriftV2",
        category: "Chat"
    )

    private let store: ModelStore
    private var generationTask: Task<Void, Never>?

    var messages: [ChatMessage] = []
    var draft: String = ""

    init(store: ModelStore) {
        self.store = store
    }

    /// Currently-loaded LLM, if any. Reading this in views participates
    /// in @Observable tracking, so the chat enables/disables itself
    /// automatically as the user loads/unloads in the Models tab.
    var loadedLLM: LLMModel? {
        store.loadedModels[.llm] as? LLMModel
    }

    var canSend: Bool {
        loadedLLM != nil
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isGenerating
    }

    var isGenerating: Bool { generationTask != nil }

    func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, let llm = loadedLLM, !isGenerating else { return }

        Self.logger.info("Send: \(prompt.count) chars, model \(llm.repoId, privacy: .public)")

        messages.append(ChatMessage(role: .user, text: prompt))
        messages.append(ChatMessage(role: .assistant, text: ""))
        draft = ""

        // Snapshot turns excluding the empty assistant placeholder.
        let turns = messages.dropLast().map { ChatTurn(role: $0.role, content: $0.text) }

        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await llm.stream(turns: turns)
                for await chunk in stream {
                    if Task.isCancelled { break }
                    self.appendToLastAssistant(chunk)
                }
                Self.logger.info("Generation finished")
            } catch is CancellationError {
                Self.logger.info("Generation cancelled")
            } catch {
                Self.logger.error("Generation failed: \(error.localizedDescription, privacy: .public)")
                self.appendToLastAssistant("\n\n[error: \(error.localizedDescription)]")
            }
            self.generationTask = nil
        }
    }

    func stop() {
        guard let task = generationTask else { return }
        Self.logger.info("User stopped generation")
        task.cancel()
        generationTask = nil
    }

    func clear() {
        stop()
        messages.removeAll()
    }

    private func appendToLastAssistant(_ chunk: String) {
        guard !messages.isEmpty,
              messages[messages.count - 1].role == .assistant else { return }
        messages[messages.count - 1].text += chunk
    }
}
