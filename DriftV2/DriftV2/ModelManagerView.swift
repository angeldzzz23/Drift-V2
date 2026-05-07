//
//  ModelManagerView.swift
//  DriftV2
//

import SwiftUI
import ModelKit

struct ModelManagerView: View {
    @Environment(ModelStore.self) private var store
    @State private var entryToDelete: ModelEntry?
    @State private var showCompatibilityWarning: ModelEntry?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DeviceSummaryRow()
                }

                ForEach(Catalog.grouped(), id: \.0) { kind, entries in
                    Section(kind.label) {
                        ForEach(entries) { entry in
                            ModelRow(
                                entry: entry,
                                store: store,
                                onDelete: { entryToDelete = entry },
                                onIncompatibleTap: { showCompatibilityWarning = entry }
                            )
                        }
                    }
                }

                StorageFooterSection(diskRevision: store.diskRevision)
            }
            .navigationTitle("Models")
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .alert(
                "Delete model?",
                isPresented: Binding(
                    get: { entryToDelete != nil },
                    set: { if !$0 { entryToDelete = nil } }
                ),
                presenting: entryToDelete
            ) { entry in
                Button("Delete", role: .destructive) {
                    store.delete(entry)
                    entryToDelete = nil
                }
                Button("Cancel", role: .cancel) { entryToDelete = nil }
            } message: { entry in
                Text("This removes \(entry.displayName) (\(formatGB(entry.approxSizeGB))) from disk.")
            }
            .alert(
                "Device may not have enough memory",
                isPresented: Binding(
                    get: { showCompatibilityWarning != nil },
                    set: { if !$0 { showCompatibilityWarning = nil } }
                ),
                presenting: showCompatibilityWarning
            ) { entry in
                Button("Download anyway") {
                    store.startDownload(entry)
                    showCompatibilityWarning = nil
                }
                Button("Cancel", role: .cancel) { showCompatibilityWarning = nil }
            } message: { entry in
                Text("\(entry.displayName) recommends \(entry.minTier.label). This device is \(Device.summary).")
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { store.lastError != nil },
                    set: { if !$0 { store.clearError() } }
                ),
                presenting: store.lastError
            ) { _ in
                Button("OK") { store.clearError() }
            } message: { msg in
                Text(msg)
            }
        }
    }

    private func formatGB(_ gb: Double) -> String {
        gb < 1 ? String(format: "%.0f MB", gb * 1000) : String(format: "%.1f GB", gb)
    }
}

// MARK: - Row

private struct ModelRow: View {
    let entry: ModelEntry
    let store: ModelStore
    let onDelete: () -> Void
    let onIncompatibleTap: () -> Void

    var body: some View {
        let downloaded = store.isDownloaded(entry)
        let downloading = store.isDownloading(entry)
        let progress = store.progress(for: entry)
        let loaded = store.isLoaded(entry)
        let loading = store.loadingEntryId == entry.id
        let compatible = Device.currentTier >= entry.minTier

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(.headline)
                    Text(entry.repoId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                statusBadge(
                    downloaded: downloaded,
                    downloading: downloading,
                    loaded: loaded,
                    loading: loading
                )
            }

            HStack(spacing: 8) {
                Label(formatGB(entry.approxSizeGB), systemImage: "internaldrive")
                Label(entry.minTier.label, systemImage: "cpu")
                if !compatible {
                    Label("Above device tier", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let note = entry.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if downloading, let p = progress {
                ProgressView(value: p) {
                    Text("Downloading \(Int(p * 100))%")
                        .font(.caption)
                }
            } else if loading {
                ProgressView {
                    Text("Loading into memory…").font(.caption)
                }
            }

            actionRow(
                downloaded: downloaded,
                downloading: downloading,
                loaded: loaded,
                loading: loading,
                compatible: compatible
            )
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusBadge(
        downloaded: Bool, downloading: Bool, loaded: Bool, loading: Bool
    ) -> some View {
        if loaded {
            badge("In memory", color: .green, system: "memorychip.fill")
        } else if loading {
            badge("Loading", color: .blue, system: "arrow.down.circle")
        } else if downloading {
            badge("Downloading", color: .blue, system: "arrow.down.circle.fill")
        } else if downloaded {
            badge("On disk", color: .accentColor, system: "checkmark.circle.fill")
        } else {
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
    private func actionRow(
        downloaded: Bool, downloading: Bool, loaded: Bool, loading: Bool, compatible: Bool
    ) -> some View {
        HStack(spacing: 8) {
            if downloading {
                Button(role: .destructive) {
                    store.cancelDownload(entry)
                } label: {
                    Label("Cancel", systemImage: "stop.circle")
                }
                .buttonStyle(.bordered)
            } else if !downloaded {
                Button {
                    if compatible { store.startDownload(entry) } else { onIncompatibleTap() }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(loading)
            } else {
                if loaded {
                    Button {
                        store.unload(entry)
                    } label: {
                        Label("Unload", systemImage: "memorychip")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        Task { await store.load(entry) }
                    } label: {
                        Label("Load", systemImage: "memorychip")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(loading)
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(loading)
            }
        }
        .controlSize(.small)
        .labelStyle(.titleAndIcon)
    }

    private func formatGB(_ gb: Double) -> String {
        gb < 1 ? String(format: "%.0f MB", gb * 1000) : String(format: "%.1f GB", gb)
    }
}

// MARK: - Device summary

private struct DeviceSummaryRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: deviceIcon)
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(Device.summary)
                    .font(.headline)
                Text("Tier: \(Device.currentTier.label)")
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

// MARK: - Storage footer

private struct StorageFooterSection: View {
    let diskRevision: Int

    var body: some View {
        Section("Storage") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "externaldrive")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("On disk")
                        .font(.headline)
                    Text(usageString)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(ModelStorage.root.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            .padding(.vertical, 4)
        }
        .id(diskRevision)
    }

    private var usageString: String {
        let bytes = diskUsage(at: ModelStorage.root)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func diskUsage(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
}

#Preview {
    ModelManagerView()
        .environment(ModelStore(registry: ModelKindRegistry()))
}
