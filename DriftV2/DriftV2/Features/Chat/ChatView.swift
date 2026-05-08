//
//  ChatView.swift
//  DriftV2
//

import SwiftUI
import ModelKit
import ModelKitMLX
import ModelKitWhisper
import Peerly

struct ChatView: View {
    @State private var vm = ChatViewModel()
    @State private var showConnectionSheet = false
    @Environment(ModelStore.self) private var store
    @Environment(PeerService.self) private var peerService

    var body: some View {
        @Bindable var vm = vm
        let loadedLLM = store.loadedModels[.llm] as? LLMModel
        let loadedWhisper = store.loadedModels[.whisper] as? WhisperModel

        NavigationStack {
            VStack(spacing: 0) {
                if loadedLLM != nil {
                    chatScroll
                } else {
                    emptyState
                }
                Divider()
                ChatInputBar(vm: vm, loadedLLM: loadedLLM, loadedWhisper: loadedWhisper)
            }
            .navigationTitle("Chat")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        showConnectionSheet = true
                    } label: {
                        Label("Connections", systemImage: connectionIcon)
                            .foregroundStyle(peerService.hasAnyConnection ? Color.accentColor : .secondary)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        vm.clear()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(vm.messages.isEmpty)
                }
            }
            .sheet(isPresented: $showConnectionSheet) {
                ConnectionSheet()
                    .environment(peerService)
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { vm.lastError != nil },
                    set: { if !$0 { vm.clearError() } }
                ),
                presenting: vm.lastError
            ) { _ in
                Button("OK") { vm.clearError() }
            } message: { msg in
                Text(msg)
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

    private var connectionIcon: String {
        peerService.hasAnyConnection
            ? "antenna.radiowaves.left.and.right.circle.fill"
            : "antenna.radiowaves.left.and.right"
    }
}

#Preview {
    ChatView()
        .environment(ModelStore(registry: ModelKindRegistry()))
        .environment(PeerService())
}
