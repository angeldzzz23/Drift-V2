//
//  ChatInputBar.swift
//  DriftV2
//

import SwiftUI
import ModelKitMLX
import ModelKitWhisper

struct ChatInputBar: View {
    @Bindable var vm: ChatViewModel
    let backend: ChatBackend?
    let transcribeBackend: TranscribeBackend?

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $vm.draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .disabled(textFieldDisabled)
                .onSubmit(send)
                .submitLabel(.send)

            micButton
            actionButton
        }
        .padding()
        .background(.bar)
    }

    private var textFieldDisabled: Bool {
        backend == nil || vm.isGenerating || vm.isRecording || vm.isTranscribing
    }

    @ViewBuilder
    private var micButton: some View {
        if vm.isTranscribing {
            ProgressView()
                .controlSize(.small)
                .frame(width: 28, height: 28)
        } else if vm.isRecording {
            Button(role: .destructive, action: stopAndTranscribe) {
                Image(systemName: "stop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating)
            }
            .buttonStyle(.plain)
        } else {
            Button(action: startRecording) {
                Image(systemName: "mic.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(!vm.canRecord(transcribeBackend: transcribeBackend))
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if vm.isGenerating {
            Button(role: .destructive, action: vm.stop) {
                Image(systemName: "stop.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
        } else {
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(!vm.canSend(backend: backend))
        }
    }

    private func send() {
        if let backend { vm.send(using: backend) }
    }

    private func startRecording() {
        Task { await vm.startRecording() }
    }

    private func stopAndTranscribe() {
        guard let backend = transcribeBackend else { return }
        Task { await vm.stopAndTranscribe(using: backend) }
    }
}
