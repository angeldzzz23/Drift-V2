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
import Peerly

struct ChatMessage: Identifiable, Hashable {
    let id = UUID()
    let role: ChatTurn.Role
    var text: String
}

/// What's pinned to the next outgoing message. Carries already-encoded
/// JPEG/PNG bytes so the wire layer doesn't have to know about UIImage
/// or NSImage.
enum ChatImageAttachment: Hashable, Sendable {
    case data(Data)

    var data: Data {
        switch self {
        case .data(let data): return data
        }
    }
}

/// Where chat sends should go. Two axes:
///   • local vs remote — direct in-memory call vs Peerly stream
///   • LLM vs VLM      — text-only vs vision-capable
///
/// `ChatView.currentBackend` picks the kind based on whether an image
/// is attached; `ChatViewModel.send` switches on the case to dispatch
/// to the right code path.
enum ChatBackend {
    case localLLM(LLMModel)
    case localVLM(VLMModel)
    case remoteLLM(client: ServiceClient<ChatContract>, peerName: String)
    case remoteVLM(client: ServiceClient<VLMChatContract>, peerName: String)

    var isLocal: Bool {
        switch self {
        case .localLLM, .localVLM: return true
        case .remoteLLM, .remoteVLM: return false
        }
    }

    var supportsImages: Bool {
        switch self {
        case .localVLM, .remoteVLM: return true
        case .localLLM, .remoteLLM: return false
        }
    }

    var displayName: String {
        switch self {
        case .localLLM, .localVLM:
            return "this device"
        case .remoteLLM(_, let name), .remoteVLM(_, let name):
            return name
        }
    }
}

/// Where the recorded audio should go for transcription. Local runs the
/// in-memory `WhisperModel`; remote sends bytes to a peer's
/// `drift.transcribe` service.
enum TranscribeBackend {
    case local(WhisperModel)
    case remote(client: ServiceClient<TranscribeContract>, peerName: String)

    var isLocal: Bool {
        if case .local = self { return true }
        return false
    }

    var displayName: String {
        switch self {
        case .local: return "this device"
        case .remote(_, let name): return name
        }
    }
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
    /// Image pinned to the next message. Send is disabled while this is
    /// non-nil (we don't ship images yet).
    var imageAttachment: ChatImageAttachment?

    /// True while the mic is actively recording.
    private(set) var isRecording: Bool = false
    /// True while a captured clip is being transcribed.
    private(set) var isTranscribing: Bool = false
    /// Surfaced to the view via an alert.
    var lastError: String?

    var isGenerating: Bool { generationTask != nil }

    func canSend(backend: ChatBackend?) -> Bool {
        guard backend != nil,
              !isGenerating,
              !isRecording,
              !isTranscribing
        else { return false }
        // Need either text or an image. An image-only send is a valid
        // VLM call ("describe this") — the wire layer handles it.
        let hasDraft = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImage = imageAttachment != nil
        return hasDraft || hasImage
    }

    func canAttachImage(loadedLLM: LLMModel?) -> Bool {
        // Mirror the gate on draft/recording so the camera button doesn't
        // accept input while another async path is running.
        imageAttachment == nil && !isRecording && !isTranscribing && !isGenerating
    }

    func canRecord(transcribeBackend: TranscribeBackend?) -> Bool {
        transcribeBackend != nil && !isRecording && !isTranscribing && !isGenerating
    }

    func send(using backend: ChatBackend) {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isGenerating else { return }

        // Snapshot the attachment now — it's consumed by this send.
        let images: [Data] = imageAttachment.map { [$0.data] } ?? []
        Self.logger.info("Send: \(prompt.count) chars, \(images.count) image(s) via \(backend.displayName, privacy: .public)")

        messages.append(ChatMessage(role: .user, text: prompt))
        messages.append(ChatMessage(role: .assistant, text: ""))
        draft = ""
        imageAttachment = nil

        // Snapshot turns excluding the empty assistant placeholder.
        let turns = messages.dropLast().map { ChatTurn(role: $0.role, content: $0.text) }

        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                switch backend {
                case .localLLM(let llm):
                    let stream = try await llm.stream(turns: turns)
                    for await chunk in stream {
                        if Task.isCancelled { break }
                        self.appendToLastAssistant(chunk)
                    }
                case .localVLM(let vlm):
                    let stream = try await vlm.stream(turns: turns, images: images)
                    for await chunk in stream {
                        if Task.isCancelled { break }
                        self.appendToLastAssistant(chunk)
                    }
                case .remoteLLM(let client, _):
                    let wire = ChatRequest(
                        turns: turns.map { ChatRequest.Turn(role: $0.role.rawValue, content: $0.content) }
                    )
                    let stream = client.stream(wire)
                    for try await chunk in stream {
                        if Task.isCancelled { break }
                        self.appendToLastAssistant(chunk.text)
                    }
                case .remoteVLM(let client, _):
                    let wire = ChatRequest(
                        turns: turns.map { ChatRequest.Turn(role: $0.role.rawValue, content: $0.content) },
                        images: images
                    )
                    let stream = client.stream(wire)
                    for try await chunk in stream {
                        if Task.isCancelled { break }
                        self.appendToLastAssistant(chunk.text)
                    }
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
        imageAttachment = nil
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

    func stopAndTranscribe(using backend: TranscribeBackend) async {
        guard isRecording, let url = recorder.stop() else {
            isRecording = false
            return
        }
        isRecording = false
        isTranscribing = true
        Self.logger.info("Recording stopped, transcribing via \(backend.displayName, privacy: .public)")

        defer {
            isTranscribing = false
            try? FileManager.default.removeItem(at: url)
        }

        do {
            let text: String
            switch backend {
            case .local(let model):
                text = try await model.transcribe(audioURL: url)
            case .remote(let client, _):
                let audioData = try Data(contentsOf: url)
                let stream = client.stream(TranscribeRequest(audio: audioData))
                var accumulated = ""
                for try await chunk in stream {
                    accumulated += chunk.text
                }
                text = accumulated
            }
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

    // MARK: - Image attachment

    /// Pin captured image bytes (JPEG/PNG) to the next message. Send is
    /// still gated until wire encoding is wired up — for now the bytes
    /// just show in the preview and `clear()` / `removeImageAttachment()`
    /// drop them.
    func attach(imageData: Data) {
        imageAttachment = .data(imageData)
        Self.logger.info("Attached image: \(imageData.count) bytes")
    }

    func removeImageAttachment() {
        guard imageAttachment != nil else { return }
        imageAttachment = nil
        Self.logger.info("Removed image attachment")
    }

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
