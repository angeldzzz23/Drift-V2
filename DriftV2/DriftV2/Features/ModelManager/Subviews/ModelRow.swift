//
//  ModelRow.swift
//  DriftV2
//

import SwiftUI
import ModelKit

struct ModelRow: View {
    let entry: ModelEntry
    let state: ModelRowState
    let isDefault: Bool
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onLoad: () -> Void
    let onUnload: () -> Void
    let onDelete: () -> Void
    let onToggleDefault: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName).font(.headline)
                    Text(entry.repoId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button(action: onToggleDefault) {
                    Image(systemName: isDefault ? "star.fill" : "star")
                        .foregroundStyle(isDefault ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help(isDefault ? "Loaded automatically on launch" : "Mark as auto-load on launch")
                statusBadge
            }

            HStack(spacing: 8) {
                Label(ModelManagerViewModel.formatGB(entry.approxSizeGB), systemImage: "internaldrive")
                Label(entry.minTier.label, systemImage: "cpu")
                if case .notDownloaded(let compatible) = state, !compatible {
                    Label("Above device tier", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let note = entry.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }

            if case .downloading(let p) = state {
                ProgressView(value: p) {
                    Text("Downloading \(Int(p * 100))%").font(.caption)
                }
            } else if case .loading = state {
                ProgressView { Text("Loading into memory…").font(.caption) }
            }

            actionRow
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch state {
        case .loaded:
            badge("In memory", color: .green, system: "memorychip.fill")
        case .loading:
            badge("Loading", color: .blue, system: "arrow.down.circle")
        case .downloading:
            badge("Downloading", color: .blue, system: "arrow.down.circle.fill")
        case .onDisk:
            badge("On disk", color: .accentColor, system: "checkmark.circle.fill")
        case .notDownloaded:
            badge("Not downloaded", color: .secondary, system: "circle.dashed")
        }
    }

    private func badge(_ text: String, color: Color, system: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: system)
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 8) {
            switch state {
            case .downloading:
                Button(role: .destructive, action: onCancel) {
                    Label("Cancel", systemImage: "stop.circle")
                }
                .buttonStyle(.bordered)
            case .notDownloaded:
                Button(action: onDownload) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
            case .loading:
                EmptyView()
            case .onDisk:
                Button(action: onLoad) {
                    Label("Load", systemImage: "memorychip")
                }
                .buttonStyle(.borderedProminent)
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            case .loaded:
                Button(action: onUnload) {
                    Label("Unload", systemImage: "memorychip")
                }
                .buttonStyle(.bordered)
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.small)
        .labelStyle(.titleAndIcon)
    }
}
