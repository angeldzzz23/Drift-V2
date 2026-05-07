//
//  ModelManagerViewModel.swift
//  DriftV2
//

import Foundation
import Observation
import ModelKit

/// Single source of truth for what to render in a row — collapses the
/// download/load/loaded boolean matrix into one value.
enum ModelRowState: Equatable {
    case notDownloaded(compatible: Bool)
    case downloading(progress: Double)
    case onDisk
    case loading
    case loaded
}

@Observable
@MainActor
final class ModelManagerViewModel {
    private let store: ModelStore

    var entryToDelete: ModelEntry?
    var compatibilityWarning: ModelEntry?

    init(store: ModelStore) {
        self.store = store
    }

    // MARK: - Read-through projections

    var groupedCatalog: [(ModelKind, [ModelEntry])] { Catalog.grouped() }

    var deviceSummary: String { Device.summary }
    var deviceTier: DeviceTier { Device.currentTier }

    var diskRevision: Int { store.diskRevision }
    var storageRoot: URL { ModelStorage.root }

    var lastError: String? { store.lastError }
    func clearError() { store.clearError() }

    func rowState(for entry: ModelEntry) -> ModelRowState {
        if store.isLoaded(entry) { return .loaded }
        if store.loadingEntryId == entry.id { return .loading }
        if store.isDownloading(entry) {
            return .downloading(progress: store.progress(for: entry) ?? 0)
        }
        if store.isDownloaded(entry) { return .onDisk }
        return .notDownloaded(compatible: deviceTier >= entry.minTier)
    }

    // MARK: - Actions

    func requestDownload(_ entry: ModelEntry) {
        if deviceTier >= entry.minTier {
            store.startDownload(entry)
        } else {
            compatibilityWarning = entry
        }
    }

    func confirmDownloadAnyway() {
        guard let entry = compatibilityWarning else { return }
        store.startDownload(entry)
        compatibilityWarning = nil
    }

    func cancelDownload(_ entry: ModelEntry) {
        store.cancelDownload(entry)
    }

    func load(_ entry: ModelEntry) async {
        await store.load(entry)
    }

    func unload(_ entry: ModelEntry) {
        store.unload(entry)
    }

    func requestDelete(_ entry: ModelEntry) {
        entryToDelete = entry
    }

    func confirmDelete() {
        guard let entry = entryToDelete else { return }
        store.delete(entry)
        entryToDelete = nil
    }

    // MARK: - Formatting helpers

    static func formatGB(_ gb: Double) -> String {
        gb < 1 ? String(format: "%.0f MB", gb * 1000) : String(format: "%.1f GB", gb)
    }
}
