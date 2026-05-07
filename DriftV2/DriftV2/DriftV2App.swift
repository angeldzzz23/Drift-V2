//
//  DriftV2App.swift
//  DriftV2
//
//  Created by angel zambrano on 5/7/26.
//

import SwiftUI
import ModelKit
import ModelKitMLX
import ModelKitWhisper

@main
struct DriftV2App: App {
    @State private var store: ModelStore

    init() {
        let registry = ModelKindRegistry()
        ModelKitMLX.register(into: registry)
        ModelKitWhisper.register(into: registry)
        _store = State(initialValue: ModelStore(registry: registry))
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
