//
//  DriftV2App.swift
//  DriftV2
//
//  Created by angel zambrano on 5/7/26.
//

import SwiftUI
import os
import ModelKit
import ModelKitMLX
import ModelKitWhisper
import Peerly

@main
struct DriftV2App: App {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DriftV2",
        category: "App"
    )

    @State private var store: ModelStore
    @State private var peerService: PeerService
    @State private var backendSelection = BackendSelection()
    @State private var hostActivityLog = HostActivityLog()
    /// Strong refs kept so Peerly's `[weak service]` capture in
    /// `RegisteredService.from` doesn't see a dealloc'd instance. We
    /// re-register these same instances on model events to refresh the
    /// metadata snapshot Peerly stores.
    @State private var chatService: ChatService
    @State private var transcribeService: TranscribeService

    init() {
        Self.logger.info("DriftV2 launching")

        let registry = ModelKindRegistry()
        ModelKitMLX.register(into: registry)
        ModelKitWhisper.register(into: registry)
        let modelStore = ModelStore(registry: registry)
        _store = State(initialValue: modelStore)

        let activity = HostActivityLog()
        _hostActivityLog = State(initialValue: activity)

        let chat = ChatService(store: modelStore, activityLog: activity)
        let transcribe = TranscribeService(store: modelStore, activityLog: activity)

        let peer = PeerService()
        peer.register(chat)
        peer.register(transcribe)
        _peerService = State(initialValue: peer)
        _chatService = State(initialValue: chat)
        _transcribeService = State(initialValue: transcribe)

        Self.logger.info("Loaders registered: MLX (llm, vlm), Whisper. Peer services: drift.chat, drift.transcribe")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(peerService)
                .environment(backendSelection)
                .environment(hostActivityLog)
                .task { await observeStoreEvents() }
                .task { await refreshServicesOnModelEvents() }
        }
        #if os(macOS)
        .defaultSize(width: 720, height: 800)
        #endif
    }

    /// Re-register the affected service whenever a model's load state
    /// changes. Peerly snapshots metadata at register time, so this is
    /// what pushes fresh `status` / `model` / `displayName` to peers.
    private func refreshServicesOnModelEvents() async {
        for await event in store.events() {
            switch event.type {
            case .loadStarted, .loaded, .loadFailed, .unloaded,
                 .downloadFinished, .downloadFailed, .deleted:
                break
            default:
                continue
            }
            if event.modelKind == .llm {
                peerService.register(chatService)
            } else if event.modelKind == .whisper {
                peerService.register(transcribeService)
            }
        }
    }

    /// Demo subscriber for the new `ModelStore.events()` AsyncStream API.
    /// Mirrors every state change to `os.Logger` under the `Events`
    /// category — visible in Xcode console and Console.app. Multiple
    /// subscribers are supported; this is one of them.
    private func observeStoreEvents() async {
        let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "DriftV2",
            category: "Events"
        )
        for await event in store.events() {
            print("HELLO: type=\(event.type.rawValue) entry=\(event.entry?.repoId ?? "n/a") kind=\(event.modelKind.id)")
            logger.info("\(event.description, privacy: .public)")
        }
    }
}
