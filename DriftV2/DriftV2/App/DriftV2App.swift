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

@main
struct DriftV2App: App {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DriftV2",
        category: "App"
    )

    @State private var store: ModelStore

    init() {
        Self.logger.info("DriftV2 launching")

        let registry = ModelKindRegistry()
        ModelKitMLX.register(into: registry)
        ModelKitWhisper.register(into: registry)
        _store = State(initialValue: ModelStore(registry: registry))

        Self.logger.info("Loaders registered: MLX (llm, vlm), Whisper")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
        #if os(macOS)
        .defaultSize(width: 720, height: 800)
        #endif
    }
}
