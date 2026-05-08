//
//  ChatViewModel.swift
//  DriftV2
//

import Foundation
import Observation
import os
import ModelKit
import ModelKitMLX
import ModelKitWhisper

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

    private var generationTask: Task<Void, Never>?
    private let recorder = AudioRecorder()

    var messages: [ChatMessage] = []
    var draft: String = ""

    /// True while the mic is actively recording.
    private(set) var isRecording: Bool = false
    /// True while a captured clip is being transcribed.
    private(set) var isTranscribing: Bool = false
    /// Surfaced to the view via an alert.
    var lastError: String?

    var isGenerating: Bool { generationTask != nil }

    func canSend(loadedLLM: LLMModel?) -> Bool {
        loadedLLM != nil
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isGenerating
            && !isRecording
            && !isTranscribing
    }

    func canRecord(loadedWhisper: WhisperModel?) -> Bool {
        loadedWhisper != nil && !isRecording && !isTranscribing && !isGenerating
    }

    func send(using llm: LLMModel) {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isGenerating else { return }

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

    // MARK: - Mic / transcribe

    func startRecording() async {
        guard !isRecording, !isTranscribing, !isGenerating else { return }

        let granted = await AudioRecorder.requestPermission()
        guard granted else {
            Self.logger.error("Mic permission denied")
            lastError = "Microphone access denied. Enable it in Settings."
            return
        }

        do {
            try recorder.start()
            isRecording = true
            Self.logger.info("Recording started")
        } catch {
            Self.logger.error("Recording start failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
    }

    func stopAndTranscribe(using model: WhisperModel) async {
        guard isRecording, let url = recorder.stop() else {
            isRecording = false
            return
        }
        isRecording = false
        isTranscribing = true
        Self.logger.info("Recording stopped, transcribing with \(model.repoId, privacy: .public)")

        defer {
            isTranscribing = false
            try? FileManager.default.removeItem(at: url)
        }

        do {
            let text = try await model.transcribe(audioURL: url)
            insertTranscribedText(text)
            Self.logger.info("Transcribe done: \(text.count) chars")
        } catch {
            Self.logger.error("Transcribe failed: \(error.localizedDescription, privacy: .public)")
            lastError = "Transcribe failed: \(error.localizedDescription)"
        }
    }

    func cancelRecording() {
        guard isRecording else { return }
        recorder.cancel()
        isRecording = false
        Self.logger.info("Recording cancelled")
    }

    func clearError() { lastError = nil }

    // MARK: - Private

    private func insertTranscribedText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft = trimmed
        } else {
            draft += " \(trimmed)"
        }
    }

    private func appendToLastAssistant(_ chunk: String) {
        guard !messages.isEmpty,
              messages[messages.count - 1].role == .assistant else { return }
        messages[messages.count - 1].text += chunk
    }
}
