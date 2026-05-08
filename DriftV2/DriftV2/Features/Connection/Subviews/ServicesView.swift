//
//  ServicesView.swift
//  DriftV2
//
//  Renders a list of `ServiceCapability` (local advertised, or a peer's
//  hello payload) as readable cards: service id + type pill + per-model
//  status row. For `type=llm` services, a "Use for chat" button writes
//  to `BackendSelection` so this device's chat sends route to the right
//  source.
//

import SwiftUI
import Peerly

enum ServiceSource: Hashable {
    case local
    case remote(Peer)
}

struct ServicesView: View {
    let services: [ServiceCapability]
    let source: ServiceSource
    /// Resolved choices from `BackendSelection` (live, recomputed by the
    /// caller every body pass). Used to highlight the auto-picked service
    /// when not in manual mode.
    let llmResolution: Resolution
    let whisperResolution: Resolution

    @Environment(RoutingPolicySelection.self) private var selection

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
                if let typeString = service.metadata["type"] {
                    let kind = ServiceKind(typeString)
                    selectionPill(
                        mode: selection.mode(for: kind),
                        manuallySelected: isManuallySelected(for: kind),
                        autoMatchesThis: autoMatchesThis(for: kind),
                        title: pillTitle(for: kind),
                        action: { applySelection(for: kind) }
                    )
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

    @ViewBuilder
    private func selectionPill(
        mode: AutoMode,
        manuallySelected: Bool,
        autoMatchesThis: Bool,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        switch mode {
        case .manual:
            if manuallySelected {
                inUsePill(title: "In use", color: .green)
            } else {
                Button(action: action) {
                    Text(title)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        case .auto, .autoBySpecs:
            if autoMatchesThis {
                inUsePill(title: "Auto-selected", color: .blue)
            } else {
                EmptyView()
            }
        }
    }

    private func inUsePill(title: String, color: Color) -> some View {
        Label(title, systemImage: "checkmark.circle.fill")
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func pillTitle(for kind: ServiceKind) -> String {
        switch kind {
        case .llm:     return "Use for chat"
        case .whisper: return "Use for transcription"
        default:       return "Use \(kind.id)"
        }
    }

    private func isManuallySelected(for kind: ServiceKind) -> Bool {
        switch source {
        case .local:
            return selection.isManuallySelectingLocal(for: kind)
        case .remote(let peer):
            return selection.isManuallySelectingRemote(peer.id, for: kind)
        }
    }

    private func autoMatchesThis(for kind: ServiceKind) -> Bool {
        let resolution: Resolution
        switch kind {
        case .llm:     resolution = llmResolution
        case .whisper: resolution = whisperResolution
        default:       return false
        }
        switch (source, resolution) {
        case (.local, .local):
            return true
        case (.remote(let peer), .remote(let peerId)):
            return peer.id == peerId
        default:
            return false
        }
    }

    private func applySelection(for kind: ServiceKind) {
        switch source {
        case .local:
            selection.useLocal(for: kind)
        case .remote(let peer):
            selection.useRemote(peer, for: kind)
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
