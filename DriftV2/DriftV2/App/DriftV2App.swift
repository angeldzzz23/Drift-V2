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
        category: "App")
 
    @State private var store: ModelStore // deals with models
    @State private var peerService: PeerService // deals with communication with devices. Transport layer mainly. Model aganostic
    @State private var backendSelection = RoutingPolicySelection() // is in charge of model selection between devices
    @State private var hostActivityLog = HostActivityLog()
    @State private var slipstreamConfig: SlipstreamConfig
    @State private var slipstreamRecorder: SlipstreamRecorder
    /// Strong refs kept so Peerly's `[weak service]` capture in
    /// `RegisteredService.from` doesn't see a dealloc'd instance. We
    /// re-register these same instances on model events to refresh the
    /// metadata snapshot Peerly stores.
    @State private var chatService: ChatService
    @State private var vlmChatService: VLMChatService
    @State private var transcribeService: TranscribeService
    /// Held so the AsyncStream of Slipstream events keeps a producer.
    @State private var slipstream: Slipstream

    init() {
        Self.logger.info("DriftV2 launching")

        // Construct the raw loaders so Slipstream can wrap each one with
        // PeerFirstLoader before registration into the model registry.
        let mlxBackend = MLXHuggingFaceBackend()
        let rawLoaders: [any ModelKindLoader] = [
            MLXLLMLoader(backend: mlxBackend),
            MLXVLMLoader(backend: mlxBackend),
            WhisperKitLoader(),
        ]

        let registry = ModelKindRegistry()
        let peer = PeerService()
        let config = SlipstreamConfig()
        let recorder = SlipstreamRecorder()

        let installedSlipstream = Slipstream.install(
            into: registry,
            loaders: rawLoaders,
            peerService: peer,
            config: config
        )

        let modelStore = ModelStore(registry: registry)
        _store = State(initialValue: modelStore)

        let activity = HostActivityLog()
        _hostActivityLog = State(initialValue: activity)

        let chat = ChatService(store: modelStore, activityLog: activity)
        let vlmChat = VLMChatService(store: modelStore, activityLog: activity)
        let transcribe = TranscribeService(store: modelStore, activityLog: activity)

        peer.register(chat)
        peer.register(vlmChat)
        peer.register(transcribe)
        _peerService = State(initialValue: peer)
        _chatService = State(initialValue: chat)
        _vlmChatService = State(initialValue: vlmChat)
        _transcribeService = State(initialValue: transcribe)
        _slipstreamConfig = State(initialValue: config)
        _slipstreamRecorder = State(initialValue: recorder)
        _slipstream = State(initialValue: installedSlipstream)

        Self.logger.info("Loaders registered: MLX (llm, vlm), Whisper. Peer services: drift.chat, drift.vlm, drift.transcribe, \(SlipstreamContract.id, privacy: .public)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(peerService)
                .environment(backendSelection)
                .environment(hostActivityLog)
                .environment(slipstreamConfig)
                .environment(slipstreamRecorder)
                .task { await observeStoreEvents() }
                .task { await refreshServicesOnModelEvents() }
                .task { await recordSlipstreamEvents() }
        }
        #if os(macOS)
        .defaultSize(width: 720, height: 800)
        #endif
    }

    /// Pipe Slipstream events into the recorder so the A/B view can render
    /// them, and log each completion for the console.
    private func recordSlipstreamEvents() async {
        let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "DriftV2",
            category: "Slipstream"
        )
        for await event in slipstream.events {
            slipstreamRecorder.record(event)
            switch event {
            case .downloadStarted(let repoId, let source, _):
                logger.info("start \(repoId, privacy: .public) source=\(String(describing: source), privacy: .public)")
            case .downloadFinished(let repoId, let source, let bytes, let wall):
                let mbps = wall > 0 ? (Double(bytes) / wall) / 1_000_000 : 0
                logger.info("done \(repoId, privacy: .public) source=\(String(describing: source), privacy: .public) bytes=\(bytes) wall=\(wall, format: .fixed(precision: 2))s rate=\(mbps, format: .fixed(precision: 1))MB/s")
            case .peerFailed(let repoId, let peer, let reason):
                logger.info("peer-failed \(repoId, privacy: .public) peer=\(peer, privacy: .public) reason=\(reason, privacy: .public)")
            case .downloadFailed(let repoId, let reason):
                logger.error("failed \(repoId, privacy: .public) reason=\(reason, privacy: .public)")
            case .progress:
                break
            }
        }
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
            } else if event.modelKind == .vlm {
                peerService.register(vlmChatService)
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
