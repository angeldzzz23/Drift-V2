//
//  ContentView.swift
//  DriftV2
//
//  Created by angel zambrano on 5/7/26.
//

import SwiftUI
import ModelKit

struct ContentView: View {
    @Environment(ModelStore.self) private var store

    var body: some View {
        ModelManagerView(store: store)
    }
}

#Preview {
    ContentView()
        .environment(ModelStore(registry: ModelKindRegistry()))
}
