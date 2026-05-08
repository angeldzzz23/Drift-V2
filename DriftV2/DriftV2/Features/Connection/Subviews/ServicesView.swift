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
    let llmResolution: BackendSelection.Resolution
    let whisperResolution: BackendSelection.Resolution

    @Environment(BackendSelection.self) private var selection

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
                if service.metadata["type"] == "llm" {
                    selectionPill(
                        mode: selection.llmMode,
                        manuallySelected: isManuallySelectedAsLLM,
                        autoMatchesThis: autoLLMMatchesThis,
                        title: "Use for chat",
                        action: applyLLMSelection
                    )
                } else if service.metadata["type"] == "whisper" {
                    selectionPill(
                        mode: selection.whisperMode,
                        manuallySelected: isManuallySelectedAsWhisper,
                        autoMatchesThis: autoWhisperMatchesThis,
                        title: "Use for transcription",
                        action: applyWhisperSelection
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
        mode: BackendSelection.AutoMode,
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

    private var isManuallySelectedAsLLM: Bool {
        switch source {
        case .local: return selection.isManuallyUsingLocalLLM
        case .remote(let peer): return selection.isManuallyUsingRemoteLLM(on: peer.id)
        }
    }

    private var isManuallySelectedAsWhisper: Bool {
        switch source {
        case .local: return selection.isManuallyUsingLocalWhisper
        case .remote(let peer): return selection.isManuallyUsingRemoteWhisper(on: peer.id)
        }
    }

    private var autoLLMMatchesThis: Bool {
        switch (source, llmResolution) {
        case (.local, .local): return true
        case (.remote(let peer), .remote(let peerId)): return peer.id == peerId
        default: return false
        }
    }

    private var autoWhisperMatchesThis: Bool {
        switch (source, whisperResolution) {
        case (.local, .local): return true
        case (.remote(let peer), .remote(let peerId)): return peer.id == peerId
        default: return false
        }
    }

    private func applyLLMSelection() {
        switch source {
        case .local: selection.useLocalLLM()
        case .remote(let peer): selection.useRemoteLLM(on: peer)
        }
    }

    private func applyWhisperSelection() {
        switch source {
        case .local: selection.useLocalWhisper()
        case .remote(let peer): selection.useRemoteWhisper(on: peer)
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
