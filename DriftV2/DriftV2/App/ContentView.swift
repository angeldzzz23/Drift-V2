//
//  ContentView.swift
//  DriftV2
//
//  Created by angel zambrano on 5/7/26.
//

import SwiftUI
import ModelKit
import Peerly

struct ContentView: View {
    
    @Environment(ModelStore.self) private var store
    @Environment(PeerService.self) private var peerService
    @Environment(RoutingPolicySelection.self) private var backendSelection

    var body: some View {
        TabView {
            Tab("Chat", systemImage: "bubble.left.and.bubble.right") {
                ChatView()
                    .environment(store)
                    .environment(peerService)
                    .environment(backendSelection)
            }
            Tab("Models", systemImage: "shippingbox") {
                ModelManagerView(store: store)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(ModelStore(registry: ModelKindRegistry()))
}
