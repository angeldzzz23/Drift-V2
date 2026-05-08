//
//  ChatInputBar.swift
//  DriftV2
//

import SwiftUI
import ModelKitMLX

struct ChatInputBar: View {
    @Bindable var vm: ChatViewModel
    let loadedLLM: LLMModel?

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $vm.draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .disabled(loadedLLM == nil || vm.isGenerating)
                .onSubmit(send)
                .submitLabel(.send)

            actionButton
        }
        .padding()
        .background(.bar)
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
            .disabled(!vm.canSend(loadedLLM: loadedLLM))
        }
    }

    private func send() {
        if let llm = loadedLLM { vm.send(using: llm) }
    }
}
