//
//  DeviceCard.swift
//  DriftV2
//

import SwiftUI
import Peerly

struct DeviceCard: View {
    let title: String
    let subtitle: String?
    let profile: DeviceProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let profile {
                VStack(alignment: .leading, spacing: 4) {
                    spec("Chip", profile.processorLabel)
                    spec("Memory", String(format: "%.0f GB", profile.memoryGB))
                    spec("OS", "\(profile.osName) \(profile.osVersion)")
                    if let battery = profile.batterySummary {
                        spec("Battery", battery)
                    }
                    if let disk = profile.diskSummary {
                        spec("Disk", disk)
                    }
                    if profile.lowPowerMode {
                        spec("Power", "Low Power Mode")
                    }
                    if profile.thermalState != .nominal && profile.thermalState != .unknown {
                        spec("Thermal", profile.thermalState.rawValue.capitalized)
                    }
                }
                .font(.caption)
            } else {
                Text("Specs unavailable until connected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func spec(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
            Spacer(minLength: 0)
        }
    }

    private var iconName: String {
        guard let profile else { return "laptopcomputer.and.iphone" }
        switch profile.formFactor {
        case .iPhone:  return "iphone"
        case .iPad:    return "ipad"
        case .mac:     return "macbook"
        case .vision:  return "vision.pro"
        case .unknown: return "laptopcomputer.and.iphone"
        }
    }
}
