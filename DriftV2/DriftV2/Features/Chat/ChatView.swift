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
    @State private var showActivitySheet = false
    @Environment(ModelStore.self) private var store
    @Environment(PeerService.self) private var peerService
    @Environment(BackendSelection.self) private var selection
    @Environment(HostActivityLog.self) private var hostActivityLog

    var body: some View {
        @Bindable var vm = vm
        let backend = currentBackend
        let transcribeBackend = currentTranscribeBackend

        NavigationStack {
            VStack(spacing: 0) {
                if backend != nil {
                    chatScroll
                } else {
                    emptyState
                }
                Divider()
                if let backend {
                    backendPill(backend)
                }
                ChatInputBar(vm: vm, backend: backend, transcribeBackend: transcribeBackend)
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
                        showActivitySheet = true
                    } label: {
                        Label("Hosted activity", systemImage: hostActivityIcon)
                            .foregroundStyle(hasRunningHostSession ? Color.accentColor : .primary)
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
                    .environment(selection)
            }
            .sheet(isPresented: $showActivitySheet) {
                HostActivityView()
                    .environment(hostActivityLog)
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
            emptyStateTitle,
            systemImage: "brain",
            description: Text(emptyStateDescription)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateTitle: String {
        switch selection.llm {
        case .local: return "No LLM loaded"
        case .remote: return "Remote LLM unavailable"
        }
    }

    private var emptyStateDescription: String {
        switch selection.llm {
        case .local:
            return "Load an LLM from the Models tab, or pick a connected device's LLM in the Connections sheet."
        case .remote(let peerId):
            if peerService.connectedPeers.contains(where: { $0.id == peerId }) {
                return "Selected peer hasn't loaded an LLM yet."
            }
            return "Selected peer is no longer connected. Pick a different source in the Connections sheet."
        }
    }

    /// Resolves the current backend from selection + live state. Returns
    /// nil when nothing usable is available (no local LLM, peer gone,
    /// peer hasn't loaded an LLM, etc.).
    private var currentBackend: ChatBackend? {
        switch selection.llm {
        case .local:
            guard let llm = store.loadedModels[.llm] as? LLMModel else { return nil }
            return .local(llm)
        case .remote(let peerId):
            guard let peer = peerService.connectedPeers.first(where: { $0.id == peerId }) else { return nil }
            guard peerHasLoaded(type: "llm", peerId: peer.id) else { return nil }
            let client = peerService.client(of: ChatContract.self, on: peer)
            return .remote(client: client, peerName: peer.displayName)
        }
    }

    /// Where the mic should send recorded audio for transcription.
    private var currentTranscribeBackend: TranscribeBackend? {
        switch selection.whisper {
        case .local:
            guard let whisper = store.loadedModels[.whisper] as? WhisperModel else { return nil }
            return .local(whisper)
        case .remote(let peerId):
            guard let peer = peerService.connectedPeers.first(where: { $0.id == peerId }) else { return nil }
            guard peerHasLoaded(type: "whisper", peerId: peer.id) else { return nil }
            let client = peerService.client(of: TranscribeContract.self, on: peer)
            return .remote(client: client, peerName: peer.displayName)
        }
    }

    /// True if the peer's hello reports a service of `type` with at least
    /// one `.loaded` model.
    private func peerHasLoaded(type: String, peerId: Peer.ID) -> Bool {
        peerService.peerHellos[peerId]?.services.contains { service in
            guard service.metadata["type"] == type else { return false }
            guard let json = service.metadata["models"],
                  let data = json.data(using: .utf8),
                  let models = try? JSONDecoder().decode([ServiceModelInfo].self, from: data)
            else { return false }
            return models.contains { $0.status == .loaded }
        } ?? false
    }

    private func backendPill(_ backend: ChatBackend) -> some View {
        HStack(spacing: 6) {
            Image(systemName: backend.isLocal ? "iphone" : "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
            Text("Using ").foregroundStyle(.secondary)
                + Text(backend.displayName).foregroundStyle(.primary).bold()
            Spacer()
            Button("Change") { showConnectionSheet = true }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial)
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

    private var hasRunningHostSession: Bool {
        hostActivityLog.sessions.contains { session in
            if case .running = session.status { return true }
            return false
        }
    }

    private var hostActivityIcon: String {
        hasRunningHostSession ? "server.rack" : "server.rack"
    }
}

#Preview {
    ChatView()
        .environment(ModelStore(registry: ModelKindRegistry()))
        .environment(PeerService())
        .environment(BackendSelection())
        .environment(HostActivityLog())
}
