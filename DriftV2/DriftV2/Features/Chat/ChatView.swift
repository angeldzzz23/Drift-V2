//
//  ChatView.swift
//  DriftV2
//

import SwiftUI
import ModelKit

struct ChatView: View {
    @State private var vm: ChatViewModel

    init(store: ModelStore) {
        _vm = State(initialValue: ChatViewModel(store: store))
    }

    var body: some View {
        @Bindable var vm = vm
        NavigationStack {
            VStack(spacing: 0) {
                if vm.loadedLLM != nil {
                    chatScroll
                } else {
                    emptyState
                }
                Divider()

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Message", text: $vm.draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)
                        .disabled(vm.loadedLLM == nil || vm.isGenerating)
                        .onSubmit { vm.send() }
                        .submitLabel(.send)

                    if vm.isGenerating {
                        Button(role: .destructive) {
                            vm.stop()
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            vm.send()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        .disabled(!vm.canSend)
                    }
                }
                .padding()
                .background(.bar)
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
    ChatView(store: ModelStore(registry: ModelKindRegistry()))
}
