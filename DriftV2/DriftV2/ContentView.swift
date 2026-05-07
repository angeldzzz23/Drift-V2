//
//  ContentView.swift
//  DriftV2
//
//  Created by angel zambrano on 5/7/26.
//

import SwiftUI
import ModelKit

struct ContentView: View {
    var body: some View {
        ModelManagerView()
    }
}

#Preview {
    ContentView()
        .environment(ModelStore(registry: ModelKindRegistry()))
}
