//
//  ServicesView.swift
//  DriftV2
//
//  Renders a list of `ServiceCapability` (local advertised, or a peer's
//  hello payload) as readable cards: service id + type pill + per-model
//  status row with name, repoId, size, and a status icon.
//

import SwiftUI
import Peerly

struct ServicesView: View {
    let services: [ServiceCapability]

    var body: some View {
        if services.isEmpty {
            Text("No services advertised")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(services, id: \.id) { service in
                    serviceCard(service)
                }
            }
        }
    }

    @ViewBuilder
    private func serviceCard(_ service: ServiceCapability) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: serviceIcon(for: service))
                    .foregroundStyle(.tint)
                Text(service.id)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let type = service.metadata["type"] {
                    Text(type)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.gray.opacity(0.15), in: Capsule())
                }
            }

            let models = Self.decodeModels(from: service.metadata["models"])
            if models.isEmpty {
                Text("No downloaded models")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            } else {
                ForEach(models, id: \.id) { model in
                    ModelStatusRow(model: model)
                }
            }
        }
    }

    private static func decodeModels(from json: String?) -> [ServiceModelInfo] {
        guard let json,
              let data = json.data(using: .utf8),
              let models = try? JSONDecoder().decode([ServiceModelInfo].self, from: data)
        else { return [] }
        return models
    }

    private func serviceIcon(for service: ServiceCapability) -> String {
        switch service.metadata["type"] {
        case "llm":     return "bubble.left.and.bubble.right"
        case "whisper": return "waveform"
        case "vlm":     return "eye"
        default:        return "shippingbox"
        }
    }
}

private struct ModelStatusRow: View {
    let model: ServiceModelInfo

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name).font(.caption)
                Text(model.id)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(String(format: "%.1f GB", model.sizeGB))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch model.status {
        case .loaded:
            Image(systemName: "memorychip.fill")
                .foregroundStyle(.green)
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .idle:
            Image(systemName: "internaldrive")
                .foregroundStyle(.secondary)
        }
    }
}
