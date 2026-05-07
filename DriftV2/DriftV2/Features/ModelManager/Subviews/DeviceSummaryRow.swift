//
//  DeviceSummaryRow.swift
//  DriftV2
//

import SwiftUI
import ModelKit

struct DeviceSummaryRow: View {
    let summary: String
    let tier: DeviceTier

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: deviceIcon)
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary).font(.headline)
                Text("Tier: \(tier.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var deviceIcon: String {
        #if os(macOS)
        "macbook"
        #else
        "iphone"
        #endif
    }
}
