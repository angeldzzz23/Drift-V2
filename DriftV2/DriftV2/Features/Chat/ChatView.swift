//
//  ChatView.swift
//  DriftV2
//

import SwiftUI
import ModelKit
import ModelKitMLX

struct ChatView: View {
    @State private var vm = ChatViewModel()
    @Environment(ModelStore.self) private var store

    var body: some View {
        let loadedLLM = store.loadedModels[.llm] as? LLMModel

        NavigationStack {
            VStack(spacing: 0) {
                if loadedLLM != nil {
                    chatScroll
                } else {
                    emptyState
                }
                Divider()
                ChatInputBar(vm: vm, loadedLLM: loadedLLM)
            }
            .navigationTitle("Chat")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        vm.clear()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(vm.messages.isEmpty)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No LLM loaded",
            systemImage: "brain",
            description: Text("Load an LLM from the Models tab to start chatting.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if vm.messages.isEmpty {
                        Text("Type a message to start.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 60)
                    }
                    ForEach(vm.messages) { msg in
                        ChatBubble(message: msg)
                            .id(msg.id)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.messages.last?.id) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: vm.messages.last?.text) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let id = vm.messages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }
}

#Preview {
    ChatView()
        .environment(ModelStore(registry: ModelKindRegistry()))
}
